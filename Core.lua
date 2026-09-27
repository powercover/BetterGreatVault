local addonName, BGV = ...

BGV.VERSION = "1.0.0"
BGV.AUTHOR = "powercover"

local Utils = BGV.Utils
local frame = CreateFrame("Frame")

local function SavedDefaults()
    if type(BetterGreatVaultCharDB) ~= "table" then
        BetterGreatVaultCharDB = {}
    end
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
        showBisTiers = true,
        remindRewards = true,
        fontSize = 0,
        useSpecAccent = true,
        accentColor = { r = 0.85, g = 0.65, b = 0.2 },
    })
    BetterGreatVaultCharDB = BetterGreatVaultDB
end

local function LoadVaultUI()
    Utils.LoadAddon("Blizzard_WeeklyRewards")
end

-- Key bindings (Bindings.xml). No key is bound until the player picks one in the game's Key
-- Bindings, where these show in a section of their own.
BINDING_HEADER_BETTERGREATVAULT = "Better Great Vault"
BINDING_NAME_BETTERGREATVAULT_VAULT = "Toggle the Great Vault"
BINDING_NAME_BETTERGREATVAULT_LOOT = "Toggle the loot table"
BINDING_NAME_BETTERGREATVAULT_DATABASE = "Toggle the loot database"
BINDING_NAME_BETTERGREATVAULT_SETTINGS = "Toggle Better Great Vault settings"

function BetterGreatVault_OnBinding(action)
    if action == "vault" then
        BGV.Minimap.ToggleVault()
    elseif action == "loot" then
        BGV.LootTable.Toggle()
    elseif action == "database" then
        BGV.LootTable.ToggleDatabase()
    elseif action == "settings" then
        BGV.Minimap.ToggleSettings()
    end
end

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
        Utils.Print("Rewards are waiting in your Great Vault.")
    end
end

local function RefreshLootLists()
    if BGV.Rewards and type(BGV.Rewards.InvalidateIcons) == "function" then
        BGV.Rewards.InvalidateIcons()
    end
    if BGV.LootTable and type(BGV.LootTable.Invalidate) == "function" then
        BGV.LootTable.Invalidate()
    end
end

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

local function AttachToVault()
    BGV.UI.Hook()
    BGV.Tooltip.Hook()
    if BGV.UI.hooked then
        BGV.UI.Prepare()
        BGV.UI.RefreshOpenFrame()
    end
end

local function PrintHelp()
    Utils.Print(string.format("v%s by %s", BGV.VERSION, BGV.AUTHOR))
    Utils.Print("/bgv debug - toggle debug and print the current Great Vault")
    Utils.Print("/bgv db - loot database: everything the vault can award, for any class")
    Utils.Print("/bgv refresh - refresh the open Great Vault")
    Utils.Print("/bgv reset - clear saved settings")
end

-- Lists every Great Vault slot in chat: progress, requirement and reward item level.
function BGV.PrintVaultData()
    BGV.GreatVault.Invalidate()
    local ok, snapshot = pcall(BGV.GreatVault.GetSnapshot)
    if not ok then
        BGV.lastError = snapshot
        Utils.Print("Could not read Great Vault data.")
        return
    end

    if BGV.lastError then
        Utils.Print("Last error: " .. tostring(BGV.lastError))
    end

    if #snapshot == 0 then
        Utils.Print("No Great Vault activities returned.")
        return
    end

    Utils.Print("Great Vault data:")
    for _, slot in ipairs(snapshot) do
        local reward = slot.itemLevel and tostring(slot.itemLevel) or "unavailable"
        Utils.Print(string.format(
            "Category: %s | Slot: %d | Progress: %d | Required: %d | Reward ilvl: %s",
            slot.category,
            slot.index,
            slot.progress,
            slot.threshold,
            reward
        ))
    end
end

-- Reads the Great Vault again, and redraws it if it's open.
function BGV.RefreshVault()
    BGV.GreatVault.Invalidate()
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.Refresh) == "function" and WeeklyRewardsFrame:IsShown() then
        local ok, err = pcall(WeeklyRewardsFrame.Refresh, WeeklyRewardsFrame)
        if not ok then
            BGV.lastError = err
            BGV.UI.RefreshOpenFrame()
        end
    else
        BGV.UI.RefreshOpenFrame()
        Utils.Print("Great Vault data refreshed. Open the Great Vault to see it.")
    end
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
    Utils.Print("Settings reset.")
end

local function HandleSlash(message)
    local command = Utils.Trim(message):lower()
    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "debug" then
        SavedDefaults()
        BetterGreatVaultDB.debug = not BetterGreatVaultDB.debug
        Utils.Print(BetterGreatVaultDB.debug and "Debug enabled." or "Debug disabled.")
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
    elseif command == "reset" then
        BGV.ResetSettings()
    else
        Utils.Print("Unknown command.")
        PrintHelp()
    end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            SavedDefaults()
            Utils.ApplyFontSize()
            BGV.Minimap.RegisterSettings()
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
        RefreshLootLists()
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
        if arg1 == true then
            remindUntil = GetTime() + REMIND_FOR
            if C_Timer and type(C_Timer.After) == "function" then
                C_Timer.After(5, RemindRewards)
            end
        end
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOOT_SPEC_UPDATED" then
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
        RefreshLootLists()
        BGV.GreatVault.Invalidate()
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
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

SLASH_BETTERGREATVAULT1 = "/bgv"
SlashCmdList.BETTERGREATVAULT = HandleSlash
