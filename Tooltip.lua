local _, BGV = ...

BGV.Tooltip = {}

local Tooltip = BGV.Tooltip
local Utils = BGV.Utils
local L = BGV.L

local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
local MAX_LISTED = 12

local function AddBlank()
    if type(GameTooltip_AddBlankLineToTooltip) == "function" then
        GameTooltip_AddBlankLineToTooltip(GameTooltip)
    else
        GameTooltip:AddLine(" ")
    end
end

local function AddHeader(text)
    GameTooltip:AddLine(text, 1, 0.82, 0)
end

local function AddBody(text, r, g, b)
    GameTooltip:AddLine(text, r or 1, g or 1, b or 1, true)
end

local function AddList(rows, formatter)
    local hidden = 0
    for index, row in ipairs(rows) do
        if index <= MAX_LISTED then
            AddBody(formatter(row))
        else
            hidden = hidden + 1
        end
    end
    if hidden > 0 then
        AddBody(string.format(L["... and %d more"], hidden), 0.7, 0.7, 0.7)
    end
end

local function AppendDungeon(slot)
    if type(slot.runs) ~= "table" or #slot.runs == 0 then
        return
    end

    AddBlank()
    AddHeader(L["Completed Activities"])
    AddList(slot.runs, function(run)
        local line = run.text or L["Mythic+"]
        if run.counts then
            line = CHECK .. line
            if run.setsReward then
                line = line .. "  " .. L["(sets reward)"]
            end
            return line
        end
        return "|cff808080" .. line .. "|r"
    end)
end

local function AppendRaid(slot)
    if type(slot.encounters) ~= "table" or #slot.encounters == 0 then
        return
    end

    AddBlank()
    AddHeader(L["Bosses"])
    local lastInstance
    local listed = 0
    local hidden = 0
    for _, encounter in ipairs(slot.encounters) do
        if listed >= MAX_LISTED then
            hidden = hidden + 1
        else
            if encounter.instanceName and encounter.instanceName ~= lastInstance then
                AddBody(encounter.instanceName, 1, 0.82, 0)
                lastInstance = encounter.instanceName
            end
            local line = encounter.name or L["Boss"]
            if encounter.defeated then
                line = CHECK .. line .. " (" .. (encounter.difficultyName or L["Defeated"]) .. ")"
                AddBody(line, 0.2, 1, 0.2)
            else
                AddBody(line, 0.5, 0.5, 0.5)
            end
            listed = listed + 1
        end
    end
    if hidden > 0 then
        AddBody(string.format(L["... and %d more"], hidden), 0.7, 0.7, 0.7)
    end
end

local function AppendWorld(slot)
    if type(slot.worldTiers) ~= "table" or #slot.worldTiers == 0 then
        return
    end

    AddBlank()
    AddHeader(L["Completed Activities"])
    AddList(slot.worldTiers, function(tier)
        local line = tier.text or L["World"]
        if tier.counts then
            return CHECK .. line
        end
        return "|cff808080" .. line .. "|r"
    end)
end

function Tooltip.ShowStandalone(activityFrame)
    if BGV.Rewards and BGV.Rewards.ShowingWeeklyProgress and not BGV.Rewards.ShowingWeeklyProgress() then
        return
    end
    if not GameTooltip or type(activityFrame) ~= "table" then
        return
    end

    local slot = activityFrame.bgvSlot
    if type(slot) ~= "table" and activityFrame.type ~= nil and activityFrame.index ~= nil then
        slot = BGV.GreatVault.SlotFor(activityFrame.type, activityFrame.index)
        if type(slot) == "table" then
            activityFrame.bgvSlot = slot
        end
    end
    if type(slot) ~= "table" then
        return
    end

    local owner = activityFrame.bgvHit or activityFrame
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT", 8, -8)
    GameTooltip:ClearLines()

    local ok, err = pcall(Tooltip.Write, slot)
    if not ok then
        Utils.NoteError("slot tooltip", err)
        GameTooltip:ClearLines()
        GameTooltip:AddLine(L["Great Vault"], 1, 0.82, 0)
        GameTooltip:AddLine(BGV.GreatVault.ProgressText(slot), 1, 1, 1, true)
        GameTooltip:Show()
    end
end

function Tooltip.Write(slot)
    AddBlank()
    AddHeader(string.format(L["Great Vault — %s"], slot.category or L["Reward"]))
    AddBlank()
    AddHeader(L["Progress"])
    local progress = BGV.GreatVault.ProgressText(slot)
    if slot.qualifier then
        progress = progress .. " (" .. slot.qualifier .. ")"
    end
    AddBody(progress)

    if type(slot.killSummary) == "string" then
        AddBlank()
        AddHeader(L["Bosses Killed"])
        AddBody(slot.killSummary)
    end

    if Utils.SameType(slot.type, Utils.ThresholdType("Activities")) then
        AppendDungeon(slot)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("Raid")) then
        AppendRaid(slot)
    elseif Utils.SameType(slot.type, Utils.ThresholdType("World")) then
        AppendWorld(slot)
    elseif slot.qualifier then
        AddBlank()
        AddHeader(L["Activity"])
        AddBody(slot.qualifier)
    end

    if Utils.IsUsableNumber(slot.nextThreshold) then
        AddBlank()
        AddHeader(L["Next Slot"])
        AddBody(string.format("%d %s", slot.nextThreshold, slot.unit or L["Activities"]))
        if Utils.IsUsableNumber(slot.nextProgress) and slot.nextProgress < slot.nextThreshold then
            AddBody(string.format(L["%d more to unlock"], slot.nextThreshold - slot.nextProgress), 0.8, 0.8, 0.8)
        end
    end

    if slot.qualifier or slot.itemQuality or Utils.IsUsableNumber(slot.itemLevel) then
        AddBlank()
        AddHeader(L["Potential Reward"])
        if slot.qualifier then
            AddBody(string.format(L["Difficulty: %s"], slot.qualifier))
        end
        local upgradeText = BGV.GreatVault.RewardText(slot)
        if upgradeText then
            AddBody(upgradeText)
        end
    end

    if type(slot.upgrade) == "table" and (slot.upgrade.nextLevel or slot.upgrade.itemLevel) then
        AddBlank()
        AddHeader(L["Higher Reward"])
        if Utils.SameType(slot.type, Utils.ThresholdType("Activities")) and Utils.IsUsableNumber(slot.upgrade.nextLevel) then
            AddBody(string.format(L["Next key level: +%d"], slot.upgrade.nextLevel))
        elseif Utils.SameType(slot.type, Utils.ThresholdType("World")) and Utils.IsUsableNumber(slot.upgrade.nextLevel) then
            AddBody(string.format(L["Next tier: %d"], slot.upgrade.nextLevel))
        elseif Utils.IsUsableNumber(slot.upgrade.nextLevel) then
            local difficultyName = Utils.DifficultyName(slot.upgrade.nextLevel)
            if difficultyName then
                AddBody(string.format(L["Next difficulty: %s"], difficultyName))
            end
        end
        if Utils.IsUsableNumber(slot.upgrade.itemLevel) then
            AddBody(string.format(L["Item level: %d"], slot.upgrade.itemLevel))
        end
    end

    GameTooltip:Show()
end
