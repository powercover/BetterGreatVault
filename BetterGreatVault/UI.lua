local _, BGV = ...

BGV.UI = {}

local UI = BGV.UI
local Utils = BGV.Utils

local function ApplyFont(fontString)
    local font = GameFontHighlightSmall:GetFont()
    if font then
        fontString:SetFont(font, 10, "OUTLINE")
    else
        fontString:SetFontObject(GameFontHighlightSmall)
    end
    fontString:SetJustifyH("CENTER")
    fontString:SetJustifyV("TOP")
    fontString:SetWordWrap(true)
    fontString:SetDrawLayer("OVERLAY", 7)
    if fontString.SetMaxLines then
        fontString:SetMaxLines(6)
    end
    if fontString.SetSpacing then
        fontString:SetSpacing(1)
    end
end

local function LayoutLines(activityFrame)
    local progress = activityFrame.bgvProgress
    local reward = activityFrame.bgvReward
    if not progress or not reward then
        return
    end

    local progressHeight = progress:GetStringHeight() or 0
    local rewardHeight = 0
    if reward:IsShown() then
        rewardHeight = reward:GetStringHeight() or 0
    end
    if progressHeight <= 0 then
        progressHeight = 12
    end

    local gap = rewardHeight > 0 and 2 or 0
    local total = progressHeight + gap + rewardHeight
    local top = total / 2

    progress:ClearAllPoints()
    progress:SetPoint("TOPLEFT", activityFrame, "LEFT", 10, top)
    progress:SetPoint("TOPRIGHT", activityFrame, "RIGHT", -10, top)
    reward:ClearAllPoints()
    reward:SetPoint("TOPLEFT", progress, "BOTTOMLEFT", 0, -2)
    reward:SetPoint("TOPRIGHT", progress, "BOTTOMRIGHT", 0, -2)
end

local function EnsureHit(activityFrame)
    if activityFrame.bgvHit then
        return
    end

    local hit = CreateFrame("Button", nil, activityFrame)
    hit:SetAllPoints(activityFrame)
    hit:RegisterForClicks("AnyUp")
    hit:EnableMouse(true)
    if hit.SetPropagateMouseClicks then
        hit:SetPropagateMouseClicks(true)
    end
    hit:SetScript("OnEnter", function()
        BGV.Tooltip.ShowStandalone(activityFrame)
    end)
    hit:SetScript("OnLeave", function()
        local owner = GameTooltip and GameTooltip:GetOwner()
        if owner == hit or owner == activityFrame then
            GameTooltip:Hide()
        end
    end)
    hit:SetScript("OnClick", function(_, button)
        if button == "LeftButton" and IsModifiedClick() and type(activityFrame.GetDisplayedItemDBID) == "function" then
            local itemDBID = activityFrame:GetDisplayedItemDBID()
            if itemDBID and C_WeeklyRewards and type(C_WeeklyRewards.GetItemHyperlink) == "function" then
                local link = C_WeeklyRewards.GetItemHyperlink(itemDBID)
                if link and type(HandleModifiedItemClick) == "function" then
                    HandleModifiedItemClick(link)
                end
            end
        end
        if not hit.SetPropagateMouseClicks and button == "LeftButton" then
            local parent = activityFrame:GetParent()
            if parent and type(parent.SelectActivity) == "function" then
                parent:SelectActivity(activityFrame)
            end
        end
    end)
    activityFrame.bgvHit = hit
end

local function EnsureLines(activityFrame)
    if not activityFrame.bgvProgress then
        local progress = activityFrame:CreateFontString(nil, "OVERLAY")
        ApplyFont(progress)

        local reward = activityFrame:CreateFontString(nil, "OVERLAY")
        ApplyFont(reward)
        reward:SetTextColor(1, 0.82, 0)

        activityFrame.bgvProgress = progress
        activityFrame.bgvReward = reward
    end

    LayoutLines(activityFrame)
    EnsureHit(activityFrame)
    if activityFrame.SetClipsChildren then
        activityFrame:SetClipsChildren(false)
    end

    local level = activityFrame:GetFrameLevel() + 8
    if activityFrame.ItemFrame and type(activityFrame.ItemFrame.GetFrameLevel) == "function" then
        level = math.max(level, activityFrame.ItemFrame:GetFrameLevel() + 2)
    end
    activityFrame.bgvHit:SetFrameLevel(level)
end

local function HideDefaultCaption(activityFrame)
    if activityFrame.Threshold then
        activityFrame.Threshold:Hide()
    end
    if activityFrame.Progress then
        activityFrame.Progress:Hide()
    end
end

local function ShowDefaultCaption(activityFrame)
    if activityFrame.Threshold then
        activityFrame.Threshold:Show()
    end
    if activityFrame.Progress then
        activityFrame.Progress:Show()
    end
end

function UI.Clear(activityFrame)
    if not activityFrame then
        return
    end

    activityFrame.bgvSlot = nil
    activityFrame.bgvToken = (activityFrame.bgvToken or 0) + 1
    if activityFrame.bgvProgress then
        activityFrame.bgvProgress:Hide()
        activityFrame.bgvReward:Hide()
    end
    ShowDefaultCaption(activityFrame)
end

local function ShowReward(activityFrame, slot, info)
    if type(info) == "table" then
        if Utils.IsUsableNumber(info.itemLevel) then
            slot.itemLevel = info.itemLevel
        end
        if type(info.qualityName) == "string" and info.qualityName ~= "" then
            slot.itemQuality = info.qualityName
        end
        if type(info.upgradeTrack) == "string" and info.upgradeTrack ~= "" then
            slot.upgradeTrack = info.upgradeTrack
        end
        if Utils.IsUsableNumber(info.upgradeLevel) then
            slot.upgradeLevel = info.upgradeLevel
        end
        if Utils.IsUsableNumber(info.upgradeMax) then
            slot.upgradeMax = info.upgradeMax
        end
    elseif Utils.IsUsableNumber(info) then
        slot.itemLevel = info
    end

    local rewardText = BGV.GreatVault.DetailText(slot)
    if rewardText then
        activityFrame.bgvReward:SetText(rewardText)
        activityFrame.bgvReward:Show()
    else
        activityFrame.bgvReward:Hide()
    end
    LayoutLines(activityFrame)
end

function UI.Apply(activityFrame, slot)
    if not activityFrame or type(slot) ~= "table" then
        return
    end

    EnsureLines(activityFrame)
    activityFrame.bgvToken = (activityFrame.bgvToken or 0) + 1
    local token = activityFrame.bgvToken
    activityFrame.bgvSlot = slot

    activityFrame.bgvProgress:SetText(BGV.GreatVault.ProgressText(slot))
    if slot.unlocked then
        activityFrame.bgvProgress:SetTextColor(0.2, 1, 0.2)
    else
        activityFrame.bgvProgress:SetTextColor(0.95, 0.95, 0.95)
    end
    activityFrame.bgvProgress:Show()
    HideDefaultCaption(activityFrame)

    local rewardText = BGV.GreatVault.DetailText(slot)
    if rewardText then
        activityFrame.bgvReward:SetText(rewardText)
        activityFrame.bgvReward:Show()
    else
        activityFrame.bgvReward:Hide()
    end
    LayoutLines(activityFrame)

    if Utils.IsUsableNumber(slot.itemLevel) or type(slot.itemQuality) == "string" then
        return
    end

    BGV.Rewards.ResolveReward(slot.source, function(info)
        if activityFrame.bgvToken ~= token or activityFrame.bgvSlot ~= slot then
            return
        end
        ShowReward(activityFrame, slot, info)
    end)
end

function UI.Update(weeklyRewardsFrame)
    if not weeklyRewardsFrame or type(weeklyRewardsFrame.GetActivityFrame) ~= "function" then
        return
    end

    BGV.GreatVault.Invalidate()
    local snapshot = BGV.GreatVault.GetSnapshot()
    local seen = {}

    for _, slot in ipairs(snapshot) do
        local activityFrame = weeklyRewardsFrame:GetActivityFrame(slot.type, slot.index)
        if activityFrame then
            seen[activityFrame] = true
            UI.Apply(activityFrame, slot)
        end
    end

    if type(weeklyRewardsFrame.Activities) == "table" then
        for _, activityFrame in ipairs(weeklyRewardsFrame.Activities) do
            if not seen[activityFrame] then
                UI.Clear(activityFrame)
            end
        end
    end
end

function UI.SafeUpdate(weeklyRewardsFrame)
    if not weeklyRewardsFrame then
        return
    end

    local ok, err = pcall(UI.Update, weeklyRewardsFrame)
    if not ok then
        BGV.lastError = err
    end
end

function UI.Hook()
    if UI.hooked or type(WeeklyRewardsMixin) ~= "table" or type(hooksecurefunc) ~= "function" then
        return false
    end

    if type(WeeklyRewardsMixin.Refresh) == "function" then
        hooksecurefunc(WeeklyRewardsMixin, "Refresh", function(self)
            UI.SafeUpdate(self)
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetProgressText) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "SetProgressText", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.OnHide) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "OnHide", function(self)
            if self.bgvProgress then
                self.bgvProgress:Hide()
                self.bgvReward:Hide()
            end
        end)
    end

    UI.hooked = true
    return true
end

function UI.RefreshOpenFrame()
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
        UI.SafeUpdate(WeeklyRewardsFrame)
    end
end
