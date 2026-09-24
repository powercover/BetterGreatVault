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

function Utils.Print(message)
    local prefix = "|cff33ddff" .. ADDON_NAME .. "|r"
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message))
end

function Utils.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
