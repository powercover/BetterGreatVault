local addonName, BGV = ...

BGV.VERSION = "1.0.0"
BGV.AUTHOR = "powercover"

local Utils = BGV.Utils
local frame = CreateFrame("Frame")

local function SavedDefaults()
    BetterGreatVaultDB = Utils.CopyDefaults(BetterGreatVaultDB, {
        debug = false,
    })
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

local function AttachToVault()
    BGV.UI.Hook()
    BGV.Tooltip.Hook()
    if BGV.UI.hooked then
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
        BetterGreatVaultDB = { debug = false }
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
        elseif arg1 == "Blizzard_WeeklyRewards" then
            AttachToVault()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        BGV.GreatVault.RequestRunData()
        if AddonIsLoaded("Blizzard_WeeklyRewards") then
            AttachToVault()
        end
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        BGV.GreatVault.PrepareForNewRuns()
        BGV.GreatVault.Invalidate()
        BGV.GreatVault.RequestRunData()
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "CHALLENGE_MODE_MAPS_UPDATE" then
        BGV.GreatVault.NoteMapsUpdated()
        BGV.GreatVault.Invalidate()
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "WEEKLY_REWARDS_UPDATE" then
        BGV.Rewards.InvalidateIcons()
        BGV.GreatVault.Invalidate()
        BGV.UI.RefreshOpenFrame()
        return
    end

    if event == "EJ_LOOT_DATA_RECIEVED" then
        BGV.Rewards.RetryEmptyIcons()
        BGV.UI.RefreshOpenFrame()
    end
end)

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("WEEKLY_REWARDS_UPDATE")
frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
frame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")

SLASH_BETTERGREATVAULT1 = "/bgv"
SlashCmdList.BETTERGREATVAULT = HandleSlash
