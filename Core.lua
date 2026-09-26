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
        showMinimap = true,
        minimapAngle = 220,
        disableAnimations = false,
        useSpecAccent = true,
        accentColor = { r = 0.85, g = 0.65, b = 0.2 },
    })
    BetterGreatVaultCharDB = BetterGreatVaultDB
end

local function AddonIsLoaded(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name)
    end
    return false
end

local function LoadVaultUI()
    if AddonIsLoaded("Blizzard_WeeklyRewards") then
        return
    end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    elseif type(LoadAddOn) == "function" then
        LoadAddOn("Blizzard_WeeklyRewards")
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
    Utils.Print("/bgv refresh - refresh the open Great Vault")
    Utils.Print("/bgv reset - clear saved settings")
end

local function PrintDebug()
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

local function HandleSlash(message)
    local command = Utils.Trim(message):lower()
    if command == "" or command == "help" then
        PrintHelp()
    elseif command == "debug" then
        SavedDefaults()
        BetterGreatVaultDB.debug = not BetterGreatVaultDB.debug
        Utils.Print(BetterGreatVaultDB.debug and "Debug enabled." or "Debug disabled.")
        if BetterGreatVaultDB.debug then
            PrintDebug()
        end
    elseif command == "refresh" then
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
    elseif command == "reset" then
        BetterGreatVaultDB = nil
        BetterGreatVaultCharDB = nil
        SavedDefaults()
        BGV.Minimap.Apply()
        if BGV.Settings and type(BGV.Settings.Refresh) == "function" then
            BGV.Settings.Refresh()
        end
        Utils.Print("Settings reset.")
    else
        Utils.Print("Unknown command.")
        PrintHelp()
    end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == addonName then
            SavedDefaults()
            BGV.Minimap.RegisterSettings()
        elseif arg1 == "Blizzard_WeeklyRewards" then
            AttachToVault()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        LoadVaultUI()
        if AddonIsLoaded("Blizzard_WeeklyRewards") then
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
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED" or event == "PLAYER_LOOT_SPEC_UPDATED" then
        RefreshLootLists()
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "WEEKLY_REWARDS_UPDATE" then
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

    if event == "EJ_LOOT_DATA_RECIEVED" then
        if BGV.LootTable and type(BGV.LootTable.Nudge) == "function" then
            BGV.LootTable.Nudge()
        end
        if WeeklyRewardsFrame and WeeklyRewardsFrame.bgvPumpWait and BGV.UI and type(BGV.UI.ScheduleContent) == "function" then
            WeeklyRewardsFrame.bgvPumpWait = nil
            if type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
                BGV.UI.ScheduleContent(WeeklyRewardsFrame)
            end
        end
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")

SLASH_BETTERGREATVAULT1 = "/bgv"
SlashCmdList.BETTERGREATVAULT = HandleSlash
