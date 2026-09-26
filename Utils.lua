local _, BGV = ...

BGV.Utils = {}

local Utils = BGV.Utils

local ADDON_NAME = "Better Great Vault"

function Utils.IsSecret(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

function Utils.IsUsableNumber(value)
    return type(value) == "number" and not Utils.IsSecret(value)
end

function Utils.IsUsableString(value)
    return type(value) == "string" and value ~= "" and not Utils.IsSecret(value)
end

-- Selective boundary wrapper. Use around Blizzard calls that may be missing or restricted.
function Utils.Call(func, ...)
    if type(func) ~= "function" then
        return
    end

    local packed = { pcall(func, ...) }
    if not packed[1] then
        return
    end

    if Utils.IsSecret(packed[2]) then
        return
    end

    return unpack(packed, 2)
end

function Utils.CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = Utils.CopyDefaults({}, value)
            else
                target[key] = value
            end
        end
    end

    return target
end

function Utils.ThresholdType(name)
    local types = Enum and Enum.WeeklyRewardChestThresholdType
    if types and types[name] ~= nil then
        return types[name]
    end
end

function Utils.SameType(left, right)
    if not Utils.IsUsableNumber(left) or not Utils.IsUsableNumber(right) then
        return false
    end
    return left == right
end

function Utils.GlobalString(key, fallback)
    local value = _G[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

function Utils.DifficultyName(difficultyID)
    if not Utils.IsUsableNumber(difficultyID) or difficultyID <= 0 then
        return nil
    end

    if DifficultyUtil and type(DifficultyUtil.GetDifficultyName) == "function" then
        local name = Utils.Call(DifficultyUtil.GetDifficultyName, difficultyID)
        if Utils.IsUsableString(name) then
            return name
        end
    end

    if type(GetDifficultyInfo) == "function" then
        local name = Utils.Call(GetDifficultyInfo, difficultyID)
        if Utils.IsUsableString(name) then
            return name
        end
    end
end

function Utils.IsHeroicDungeonTier(activityTierID)
    if not Utils.IsUsableNumber(activityTierID) then
        return false
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetDifficultyIDForActivityTier) == "function") then
        return false
    end

    local difficultyID = Utils.Call(C_WeeklyRewards.GetDifficultyIDForActivityTier, activityTierID)
    if not Utils.IsUsableNumber(difficultyID) then
        return false
    end

    local heroicID = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic
    return heroicID ~= nil and difficultyID == heroicID
end

function Utils.IsAddonLoaded(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name)
    end
    return false
end

function Utils.LoadAddon(name)
    if Utils.IsAddonLoaded(name) then
        return
    end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn(name)
    elseif type(LoadAddOn) == "function" then
        LoadAddOn(name)
    end
end

function Utils.Print(message)
    local prefix = "|cff33ddff" .. ADDON_NAME .. "|r"
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message))
end

function Utils.CurrentSpecID()
    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
    if not specIndex or type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    return GetSpecializationInfo(specIndex)
end

-- The spec whose gear should be shown: Blizzard's Loot Specialization setting when the
-- player has one chosen, otherwise the active specialization (Loot Specialization returns
-- 0 for "Current Specialization").
function Utils.LootSpecID()
    local lootSpec = type(GetLootSpecialization) == "function" and GetLootSpecialization() or nil
    if Utils.IsUsableNumber(lootSpec) and lootSpec ~= 0 then
        return lootSpec
    end
    return Utils.CurrentSpecID()
end

-- Whether the player has an explicit Loot Specialization chosen (as opposed to "Current Specialization").
function Utils.HasExplicitLootSpec()
    local lootSpec = type(GetLootSpecialization) == "function" and GetLootSpecialization() or nil
    return Utils.IsUsableNumber(lootSpec) and lootSpec ~= 0
end

function Utils.LootSpecName(specID)
    if not Utils.IsUsableNumber(specID) or type(GetSpecializationInfoByID) ~= "function" then
        return nil
    end
    local _, name = Utils.Call(GetSpecializationInfoByID, specID)
    if Utils.IsUsableString(name) then
        return name
    end
end

-- Every specialization the player's own class can be, regardless of which is active.
function Utils.AvailableSpecs()
    local list = {}
    if type(GetNumSpecializations) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return list
    end
    local count = Utils.Call(GetNumSpecializations) or 0
    for index = 1, count do
        local id, name, _, icon = Utils.Call(GetSpecializationInfo, index)
        if Utils.IsUsableNumber(id) and Utils.IsUsableString(name) then
            list[#list + 1] = { id = id, name = name, icon = icon }
        end
    end
    return list
end

-- specID = nil/0 restores "Current Specialization".
function Utils.SetLootSpec(specID)
    if type(SetLootSpecialization) ~= "function" then
        return
    end
    Utils.Call(SetLootSpecialization, specID or 0)
end

function Utils.LootSpecLabel()
    local specID = Utils.LootSpecID()
    local name = Utils.LootSpecName(specID) or "Unknown"
    if Utils.HasExplicitLootSpec() then
        return name
    end
    return name .. " (current)"
end

-- Fallback for clients without MenuUtil: steps to the next class specialization.
function Utils.CycleLootSpec()
    local specs = Utils.AvailableSpecs()
    if #specs == 0 then
        return
    end
    local current = Utils.LootSpecID()
    local nextIndex = 1
    for index, spec in ipairs(specs) do
        if spec.id == current then
            nextIndex = index % #specs + 1
            break
        end
    end
    Utils.SetLootSpec(specs[nextIndex].id)
end

function Utils.LootSpecButtonEnabled()
    return not BetterGreatVaultDB or BetterGreatVaultDB.showLootSpecButton ~= false
end

-- The Loot Spec button used by both the Great Vault and the loot table; callers only position it.
function Utils.CreateLootSpecButton(parent)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(170, 20)
    button:SetScript("OnClick", function(self)
        if not Utils.OpenLootSpecMenu(self) then
            Utils.CycleLootSpec()
        end
    end)
    return button
end

function Utils.RefreshLootSpecButton(button)
    if not button then
        return
    end
    if not Utils.LootSpecButtonEnabled() then
        button:Hide()
        return
    end
    button:SetText("Loot Spec: " .. Utils.LootSpecLabel())
    button:Show()
end

-- Returns true if a dropdown menu was opened at `anchor`, false if the client has no MenuUtil
-- and the caller should fall back to something like Utils.CycleLootSpec().
function Utils.OpenLootSpecMenu(anchor)
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        return false
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateRadio("Current Specialization", function()
            return not Utils.HasExplicitLootSpec()
        end, function()
            Utils.SetLootSpec(0)
        end)
        for _, spec in ipairs(Utils.AvailableSpecs()) do
            root:CreateRadio(spec.name, function()
                return Utils.HasExplicitLootSpec() and Utils.LootSpecID() == spec.id
            end, function()
                Utils.SetLootSpec(spec.id)
            end)
        end
    end)
    return true
end

-- A flat-colored texture, used throughout the addon's custom frames (settings panel, loot table).
function Utils.Pixel(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetVertexColor(r, g, b, a or 1)
    return texture
end

function Utils.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
