local addonName, BGV = ...

BGV.VERSION = "1.0.1"
BGV.AUTHOR = "powercover"

local Utils = BGV.Utils
local L = BGV.L
local frame = CreateFrame("Frame")

local function SavedDefaults()
    if type(BetterGreatVaultCharDB) ~= "table" then
        BetterGreatVaultCharDB = {}
    end
    -- Timings a diagnostic build kept, if one ran.
    BetterGreatVaultCharDB.diag = nil
    BetterGreatVaultDB = Utils.CopyDefaults(BetterGreatVaultCharDB, {
        debug = false,
        openLootTable = true,
        showLootSpecButton = true,
        showMinimap = true,
        useCompartment = true,
        minimapPopup = true,
        popupWeek = true,
        independentMinimap = false,
        fadeMinimap = false,
        lockMinimap = false,
        minimapAngle = 220,
        disableAnimations = false,
        vaultStyle = "spec",
        showBisTiers = true,
        remindRewards = true,
        fontSize = 0,
        language = "auto",
        useSpecAccent = true,
        accentColor = { r = 0.85, g = 0.65, b = 0.2 },
    })
    BetterGreatVaultCharDB = BetterGreatVaultDB
end

local function LoadVaultUI()
    Utils.LoadAddon("Blizzard_WeeklyRewards")
end

-- Key bindings (Bindings.xml). No key is bound until the player picks one in the game's Key
-- Bindings, where these show in a section of their own. Named again in the chosen language once
-- the settings are loaded.
local function NameBindings()
    BINDING_HEADER_BETTERGREATVAULT = "Better Great Vault"
    BINDING_NAME_BETTERGREATVAULT_VAULT = L["Toggle the Great Vault"]
    BINDING_NAME_BETTERGREATVAULT_LOOT = L["Toggle the loot table"]
    BINDING_NAME_BETTERGREATVAULT_DATABASE = L["Toggle the loot database"]
    BINDING_NAME_BETTERGREATVAULT_SETTINGS = L["Toggle Better Great Vault settings"]
end

NameBindings()

BetterGreatVault_OnBinding = Utils.Protect("key binding", function(action)
    if action == "vault" then
        BGV.Minimap.ToggleVault()
    elseif action == "loot" then
        BGV.LootTable.Toggle()
    elseif action == "database" then
        BGV.LootTable.ToggleDatabase()
    elseif action == "settings" then
        BGV.Minimap.ToggleSettings()
    end
end)

-- At login, a line in chat if rewards are waiting in the Great Vault (settings). The vault's data
-- can arrive a little after login, so it's looked at again for a short while.
local REMIND_FOR = 60
local remindUntil

local function RemindRewards()
    if not remindUntil then
        return
    end
    if GetTime() > remindUntil or not (BetterGreatVaultDB and BetterGreatVaultDB.remindRewards ~= false) then
        remindUntil = nil
        return
    end
    if C_WeeklyRewards and type(C_WeeklyRewards.HasAvailableRewards) == "function"
        and C_WeeklyRewards.HasAvailableRewards() == true then
        remindUntil = nil
        Utils.Print(L["Rewards are waiting in your Great Vault."])
    end
end

-- Every loot list read again: the loot table's (which drops Rewards' lists and journal reads too)
-- and the vault's reels.
local function RefreshLootLists()
    if BGV.LootTable and type(BGV.LootTable.Invalidate) == "function" then
        BGV.LootTable.Invalidate()
    elseif BGV.Rewards and type(BGV.Rewards.InvalidateIcons) == "function" then
        BGV.Rewards.InvalidateIcons()
    end
end

-- The vault's slots when the loot lists were last read again (GreatVault.Signature).
local listsSignature

-- Restarts the vault's reel preload if it stopped to wait for journal data (or `always`).
local function ResumePump(always)
    local vault = WeeklyRewardsFrame
    if not (vault and (vault.bgvPumpWait or always) and BGV.UI and type(BGV.UI.ScheduleContent) == "function") then
        return
    end
    vault.bgvPumpWait = nil
    if type(vault.IsShown) == "function" and vault:IsShown() then
        BGV.UI.ScheduleContent(vault)
    end
end

-- A list Rewards gave up on can complete once a missing item loads (itemID) or the journal reports
-- new loot (nil): re-read those lists and refresh what shows them. Returns true if any were.
function BGV.RetryLootLists(itemID)
    if not (BGV.Rewards and type(BGV.Rewards.RetryGivenUp) == "function" and BGV.Rewards.RetryGivenUp(itemID)) then
        return false
    end
    if BGV.LootTable and type(BGV.LootTable.Reload) == "function" then
        BGV.LootTable.Reload()
    end
    ResumePump(true)
    return true
end

-- Hooks Blizzard's vault once it has loaded (its ADDON_LOADED fires inside the LoadAddOn at login,
-- so this can be asked twice). The addon's slots are laid out on its first show, by the hook on its
-- own refresh: nothing of Blizzard's is run from here.
local attached = false

local function AttachToVault()
    if attached then
        return
    end
    BGV.UI.Hook()
    if BGV.UI.hooked then
        attached = true
        BGV.UI.RefreshOpenFrame()
    end
end

local function PrintHelp()
    Utils.Print(string.format(L["Version %s by %s"], BGV.VERSION, BGV.AUTHOR))
    Utils.Print("/bgv status - " .. L["this week's Great Vault"])
    Utils.Print("/bgv db - " .. L["loot database: everything the vault can award, for any class"])
    Utils.Print("/bgv debug - " .. L["debug mode, and print the Great Vault's slots"])
    Utils.Print("/bgv refresh - " .. L["read the Great Vault again"])
    Utils.Print("/bgv perf - " .. L["what the addon costs: CPU, memory and animations"])
    Utils.Print("/bgv reset - " .. L["reset settings"])
end

-- What the addon costs: its CPU time a frame from the game's addon profiler (the figures the
-- AddOns list shows, worked out the same way; the profiler counts from when the game started,
-- through reloads), its memory, and its own timing of loading, the last slot animation (Case.lua)
-- and the last loot table load (LootTable.lua).
function BGV.PrintPerformance()
    local function Line(text)
        DEFAULT_CHAT_FRAME:AddMessage("    " .. text)
    end
    Utils.Print(L["Performance"])
    local profiler = C_AddOnProfiler
    local metrics = Enum and Enum.AddOnProfilerMetric
    if profiler and metrics and type(profiler.IsEnabled) == "function" and profiler.IsEnabled() then
        local function Metric(metric)
            return profiler.GetAddOnMetric(addonName, metric) or 0
        end
        local recent = Metric(metrics.RecentAverageTime)
        local game = profiler.GetApplicationMetric(metrics.RecentAverageTime) or 0
        local addons = profiler.GetOverallMetric(metrics.RecentAverageTime) or 0
        local total = game - addons + recent
        local share = total > 0 and recent / total * 100 or 0
        Line(string.format(L["CPU: %.3f ms a frame now (%.2f%% of the game's time); since the game started, %.3f ms on average and %.1f ms at the peak"],
            recent, share, Metric(metrics.SessionAverageTime), Metric(metrics.PeakTime)))
        Line(string.format(L["Frames where it took over 5 ms since the game started: %d"], Metric(metrics.CountTimeOver5Ms)))
    else
        Line(L["The game's addon profiler is off, so there are no CPU figures."])
    end
    if type(UpdateAddOnMemoryUsage) == "function" and type(GetAddOnMemoryUsage) == "function" then
        UpdateAddOnMemoryUsage()
        Line(string.format(L["Memory: %.1f MB"], (GetAddOnMemoryUsage(addonName) or 0) / 1024))
    end
    if BGV.loadFiles then
        local setup = BGV.loadSetup or 0
        Line(string.format(L["Loading: %.1f ms (its files %.1f ms, setting up %.1f ms)"], BGV.loadFiles + setup, BGV.loadFiles, setup))
    end
    local stats = BGV.Case and BGV.Case.lastStats
    if stats and stats.frames > 0 then
        local fps = stats.seconds > 0 and stats.frames / stats.seconds or 0
        Line(string.format(L["Last slot animation: %.3f ms a frame on average, %.3f ms at most, %d frames at %.0f fps"],
            stats.time / stats.frames, stats.peak, stats.frames, fps))
    else
        Line(L["Point at an unlocked slot in the Great Vault, then run this again to see what its animation costs."])
    end
    local reveal = BGV.UI and BGV.UI.lastReveal
    if reveal then
        Line(string.format(L["Last reward reveal: the vault opened in %.1f ms, then %d reel passes, %.1f ms at most"],
            reveal.open, reveal.passes, reveal.passPeak))
    end
    local load = BGV.LootTable and BGV.LootTable.lastLoad
    if load and load.redraws > 0 then
        Line(string.format(L["Last loot table load: %.1f ms in all, the longest redraw %.1f ms, redraws: %d"],
            load.time, load.peak, load.redraws))
    end
    Line(L["The AddOns list (Esc > AddOns) shows the same CPU figures for every addon."])
end

-- Lists every Great Vault slot in chat: progress, requirement and reward item level.
function BGV.PrintVaultData()
    BGV.GreatVault.Invalidate()
    local ok, snapshot = pcall(BGV.GreatVault.GetSnapshot)
    if not ok then
        Utils.NoteError("vault data", snapshot)
        Utils.Print(L["Could not read Great Vault data."])
        return
    end

    -- the errors the addon caught (Utils.Protect), each once, with how often it happened
    for _, caught in ipairs(BGV.errors or {}) do
        Utils.Print(string.format(L["Last error: %s"], string.format("%s (%s, x%d)", caught.message, caught.label, caught.count)))
    end

    if #snapshot == 0 then
        Utils.Print(L["No Great Vault activities returned."])
        return
    end

    Utils.Print(L["Great Vault data:"])
    for _, slot in ipairs(snapshot) do
        local reward = slot.itemLevel and tostring(slot.itemLevel) or L["unavailable"]
        Utils.Print(string.format(
            L["Category: %s | Slot: %d | Progress: %d | Required: %d | Reward ilvl: %s"],
            tostring(slot.category),
            Utils.IsUsableNumber(slot.index) and slot.index or 0,
            Utils.IsUsableNumber(slot.progress) and slot.progress or 0,
            Utils.IsUsableNumber(slot.threshold) and slot.threshold or 0,
            reward
        ))
    end
end

-- This week's Great Vault in chat, like the minimap popup.
function BGV.PrintStatus()
    local lines = BGV.Minimap.StatusLines()
    Utils.Print(lines[1] or L["Your weekly Great Vault"])
    for index = 2, #lines do
        DEFAULT_CHAT_FRAME:AddMessage("    " .. lines[index])
    end
end

-- Reads the Great Vault again, and redraws it if it's open.
function BGV.RefreshVault()
    BGV.GreatVault.Invalidate()
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.Refresh) == "function" and WeeklyRewardsFrame:IsShown() then
        local ok, err = pcall(WeeklyRewardsFrame.Refresh, WeeklyRewardsFrame)
        if not ok then
            Utils.NoteError("vault refresh", err)
            BGV.UI.RefreshOpenFrame()
        end
    else
        BGV.UI.RefreshOpenFrame()
        Utils.Print(L["Great Vault data refreshed. Open the Great Vault to see it."])
    end
    BGV.Minimap.RefreshBroker()
end

-- Puts every option back to its default. What the addon learned about this season's rewards is
-- kept: it isn't a setting, and the loot database reads item levels from it.
function BGV.ResetSettings()
    local learned = type(BetterGreatVaultDB) == "table" and BetterGreatVaultDB.rewardData or nil
    BetterGreatVaultDB = nil
    BetterGreatVaultCharDB = nil
    SavedDefaults()
    BetterGreatVaultDB.rewardData = learned
    Utils.ApplyFontSize()
    BGV.Minimap.Apply(true)
    BGV.Minimap.ApplyCompartment()
    if BGV.Settings and type(BGV.Settings.Refresh) == "function" then
        BGV.Settings.Refresh()
        BGV.Settings.Relayout()
    end
    if BGV.Settings and type(BGV.Settings.RefreshAccent) == "function" then
        BGV.Settings.RefreshAccent()
    end
    Utils.Print(L["Settings reset."])
end

local function HandleSlash(message)
    local command = Utils.Trim(message):lower()
    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "status" then
        BGV.PrintStatus()
    elseif command == "debug" then
        SavedDefaults()
        BetterGreatVaultDB.debug = not BetterGreatVaultDB.debug
        Utils.Print(BetterGreatVaultDB.debug and L["Debug enabled."] or L["Debug disabled."])
        if BetterGreatVaultDB.debug then
            BGV.PrintVaultData()
        end
        if BGV.Settings and type(BGV.Settings.Refresh) == "function" then
            BGV.Settings.Refresh()
        end
    elseif command == "db" or command == "database" then
        if BGV.LootTable and type(BGV.LootTable.ToggleDatabase) == "function" then
            BGV.LootTable.ToggleDatabase()
        end
    elseif command == "refresh" then
        BGV.RefreshVault()
    elseif command == "perf" or command == "performance" then
        BGV.PrintPerformance()
    elseif command == "reset" then
        BGV.ResetSettings()
    else
        Utils.Print(L["Unknown command."])
        PrintHelp()
    end
end

-- Every game event the addon reacts to; an error in one is noted (Utils.Protect), never shown.
frame:SetScript("OnEvent", Utils.Protect("event", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
            SavedDefaults()
            -- The chosen language first: everything built from here on speaks it.
            BGV.Locale.Apply()
            NameBindings()
            Utils.ApplyFontSize()
            BGV.Minimap.RegisterSettings()
            if started then
                BGV.loadSetup = debugprofilestop() - started
            end
        elseif arg1 == "Blizzard_WeeklyRewards" then
            AttachToVault()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        LoadVaultUI()
        if Utils.IsAddonLoaded("Blizzard_WeeklyRewards") then
            AttachToVault()
        end
        BGV.Minimap.RegisterBroker()
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        BGV.GreatVault.PrepareForNewRuns()
        BGV.GreatVault.Invalidate()
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "CHALLENGE_MODE_MAPS_UPDATE" then
        BGV.GreatVault.NoteMapsUpdated()
        BGV.GreatVault.Invalidate()
        -- Blizzard's vault and Mythic+ tab ask for map info every time they show. The season's
        -- dungeons don't change: the lists are read again only while they weren't all known.
        if not (BGV.Rewards and type(BGV.Rewards.MythicMapsKnown) == "function" and BGV.Rewards.MythicMapsKnown()) then
            RefreshLootLists()
        end
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if BGV.LootTable and type(BGV.LootTable.OnCharacterChanged) == "function" then
            BGV.LootTable.OnCharacterChanged()
        end
        -- The addon compartment lists the addon on entering the world; then take it out if it's off.
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0, BGV.Minimap.ApplyCompartment)
        end
        -- A data bar addon may have brought LibDataBroker after login.
        BGV.Minimap.RegisterBroker()
        BGV.Minimap.RefreshBroker()
        if arg1 == true then
            remindUntil = GetTime() + REMIND_FOR
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(5, RemindRewards)
            end
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOOT_SPEC_UPDATED" then
        -- PLAYER_SPECIALIZATION_CHANGED comes for group members too (their unit)
        if event == "PLAYER_SPECIALIZATION_CHANGED" and arg1 ~= nil and arg1 ~= "player" then
            return
        end
        RefreshLootLists()
        BGV.UI.RefreshOpenFrame()
        -- Start loading the new spec's reel lists right away, so hovering a slot doesn't find
        -- an empty reel while they load.
        if WeeklyRewardsFrame then
            WeeklyRewardsFrame.bgvPumping = nil
            WeeklyRewardsFrame.bgvPumpIndex = nil
            WeeklyRewardsFrame.bgvPumpWait = nil
            WeeklyRewardsFrame.bgvPumpCount = nil
            if type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
                BGV.UI.ScheduleContent(WeeklyRewardsFrame)
            end
        end
        return
    end

    if event == "WEEKLY_REWARDS_UPDATE" then
        RemindRewards()
        if BGV.Minimap and type(BGV.Minimap.RefreshAttention) == "function" then
            BGV.Minimap.RefreshAttention()
        end
        -- Blizzard's vault reports an update every time it's shown. The lists are read again when
        -- the vault's slots have changed (a list is keyed by what its slot holds, so this only
        -- spares reads nothing changed).
        local signature = BGV.GreatVault.Signature()
        if signature == nil or signature ~= listsSignature then
            listsSignature = signature
            RefreshLootLists()
        end
        BGV.GreatVault.Invalidate()
        BGV.Minimap.RefreshBroker()
        if WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
            BGV.UI.RefreshOpenFrame()
            BGV.UI.ScheduleContent(WeeklyRewardsFrame)
        elseif WeeklyRewardsFrame then
            WeeklyRewardsFrame.bgvShellReady = nil
            WeeklyRewardsFrame.bgvPumping = nil
            WeeklyRewardsFrame.bgvPumpIndex = nil
            WeeklyRewardsFrame.bgvPumpWait = nil
        end
        return
    end

    if event == "EJ_LOOT_DATA_RECIEVED" or event == "GET_ITEM_INFO_RECEIVED" then
        -- Fired inside our own scans by the journal changes they make; that isn't new data.
        if BGV.Rewards and type(BGV.Rewards.IsScanning) == "function" and BGV.Rewards.IsScanning() then
            return
        end
        if BGV.RetryLootLists(arg1) or event == "GET_ITEM_INFO_RECEIVED" then
            return
        end
        if BGV.LootTable and type(BGV.LootTable.Nudge) == "function" then
            BGV.LootTable.Nudge()
        end
        ResumePump(false)
    end
end))

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
-- The game sends GET_ITEM_INFO_RECEIVED for every item it loads, anywhere: listen only while a loot
-- list waits for one (Rewards.WaitingForItems).
if BGV.Rewards then
    BGV.Rewards.OnItemWaitChanged = function()
        if BGV.Rewards.WaitingForItems() then
            frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
        else
            frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
        end
    end
end
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

SLASH_BETTERGREATVAULT1 = "/bgv"
SlashCmdList.BETTERGREATVAULT = Utils.Protect("chat command", HandleSlash)

-- The last file the game loads (see the TOC): how long loading the addon's files took.
if BGV.loadStarted then
    BGV.loadFiles = debugprofilestop() - BGV.loadStarted
end
