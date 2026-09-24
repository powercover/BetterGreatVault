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

local CASE_ICON = 40
local CASE_STRIDE = 56
local CASE_SLOTS = 12

local function ColorTexture(texture, r, g, b, a)
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a or 1)
    else
        texture:SetTexture("Interface\\Buttons\\WHITE8X8")
        texture:SetVertexColor(r, g, b, a or 1)
    end
end

local function EnsureFX(activityFrame)
    if activityFrame.bgvFX then
        return
    end

    local fx = CreateFrame("Frame", nil, activityFrame)
    fx:SetPoint("TOPLEFT", activityFrame, "TOPLEFT", 0, 0)
    fx:SetPoint("BOTTOMRIGHT", activityFrame, "BOTTOMRIGHT", 0, 0)
    fx:EnableMouse(false)
    if fx.SetClipsChildren then
        fx:SetClipsChildren(true)
    end

    local shade = fx:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    ColorTexture(shade, 0.02, 0.015, 0.01, 0.92)

    local reel = CreateFrame("Frame", nil, fx)
    reel:SetWidth(CASE_STRIDE * CASE_SLOTS)
    reel:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
    reel:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", 0, 0)
    fx.reel = reel
    fx.cells = {}
    for index = 1, CASE_SLOTS do
        local holder = CreateFrame("Frame", nil, reel)
        holder:SetWidth(CASE_STRIDE)
        holder:SetPoint("TOPLEFT", reel, "TOPLEFT", (index - 1) * CASE_STRIDE, 0)
        holder:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", (index - 1) * CASE_STRIDE, 0)
        local back = holder:CreateTexture(nil, "BACKGROUND")
        back:SetAllPoints()
        back:Hide()
        holder.back = back
        local icon = holder:CreateTexture(nil, "ARTWORK")
        icon:SetSize(CASE_ICON, CASE_ICON)
        icon:SetPoint("CENTER", holder, "CENTER", 0, 0)
        holder.icon = icon
        fx.cells[index] = holder
    end

    local function MakeGate(anchor)
        local gate = CreateFrame("Frame", nil, activityFrame)
        gate:SetFrameLevel(activityFrame:GetFrameLevel() + 8)
        gate:EnableMouse(false)
        if gate.SetClipsChildren then
            gate:SetClipsChildren(true)
        end
        if anchor == "TOP" then
            gate:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
            gate:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        else
            gate:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", 0, 0)
            gate:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
        end

        local backing = gate:CreateTexture(nil, "BACKGROUND")
        backing:SetAllPoints(gate)
        ColorTexture(backing, 0.07, 0.06, 0.05, 1)

        local face = gate:CreateTexture(nil, "ARTWORK")
        face:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        face:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
        face:SetAlpha(1)
        if face.SetAtlas then
            face:SetAtlas("evergreen-weeklyrewards-reward-unlocked")
        else
            ColorTexture(face, 0.12, 0.10, 0.08, 1)
        end
        gate.face = face
        gate:SetAlpha(1)
        gate:Hide()
        return gate
    end

    fx.topDoor = MakeGate("TOP")
    fx.bottomDoor = MakeGate("BOTTOM")

    local marker = fx:CreateTexture(nil, "OVERLAY")
    marker:SetPoint("TOP", fx, "TOP", 0, -3)
    marker:SetPoint("BOTTOM", fx, "BOTTOM", 0, 3)
    marker:SetWidth(2)
    ColorTexture(marker, 1, 0.9, 0.45, 0.95)

    local function AddScale(group, fromY, toY, duration, smoothing)
        local scale = group:CreateAnimation("Scale")
        scale:SetDuration(duration)
        if scale.SetScaleFrom then
            scale:SetScaleFrom(1, fromY)
            scale:SetScaleTo(1, toY)
        else
            scale:SetScale(1, toY)
        end
        if scale.SetOrigin then
            scale:SetOrigin("CENTER", 0, 0)
        end
        if smoothing and scale.SetSmoothing then
            scale:SetSmoothing(smoothing)
        end
    end

    local open = fx:CreateAnimationGroup()
    AddScale(open, 0.05, 1, 0.51, "OUT")
    fx.open = open

    local close = fx:CreateAnimationGroup()
    AddScale(close, 1, 0.05, 0.51, "IN")
    close:SetScript("OnFinished", function()
        fx:Hide()
    end)
    fx.close = close

    fx.offset = 0
    fx.cursor = 1
    fx.reveal = 0
    fx.owner = activityFrame
    fx:Hide()
    activityFrame.bgvFX = fx
end

local TIER_BACK = {
    D = { 0.45, 0.45, 0.45 },
    C = { 0.12, 0.55, 0.18 },
    B = { 0.15, 0.35, 0.85 },
    A = { 0.55, 0.22, 0.78 },
    S = { 0.85, 0.62, 0.08 },
}

local function LayoutDoors(fx)
    local height = fx:GetHeight()
    if not height or height < 4 then
        height = 64
    end
    local covered = height * 0.5 * (1 - (fx.reveal or 0))
    fx:SetAlpha(1)
    local level = fx:GetFrameLevel()
    if fx.topDoor then
        fx.topDoor:SetFrameLevel(level + 6)
        fx.bottomDoor:SetFrameLevel(level + 6)
    end
    for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
        if covered < 2 then
            gate:Hide()
        else
            gate:SetHeight(covered)
            gate:Show()
        end
    end
end

local function FadeCaption(activityFrame, alpha)
    local text = activityFrame and activityFrame.bgvText
    if not text then
        return
    end
    text.bgvFadeTarget = alpha
    if text.bgvFade then
        text.bgvFade:Stop()
    end
    local from = text:GetAlpha() or 1
    local function Lock()
        text:SetAlpha(text.bgvFadeTarget or alpha)
        if activityFrame.bgvProgress then
            activityFrame.bgvProgress:SetAlpha(1)
        end
        if activityFrame.bgvReward then
            activityFrame.bgvReward:SetAlpha(1)
        end
    end
    if math.abs(from - alpha) < 0.02 then
        Lock()
        return
    end
    if not text.bgvFade then
        local group = text:CreateAnimationGroup()
        local anim = group:CreateAnimation("Alpha")
        if anim.SetSmoothing then
            anim:SetSmoothing("NONE")
        end
        group.anim = anim
        group:SetScript("OnFinished", Lock)
        text.bgvFade = group
    end
    local anim = text.bgvFade.anim
    anim:SetDuration(0.1)
    if anim.SetFromAlpha then
        anim:SetFromAlpha(from)
        anim:SetToAlpha(alpha)
    else
        anim:SetChange(alpha - from)
    end
    text.bgvFade:Play()
end

local function StopReel(fx)
    if fx.ticker then
        fx.ticker:Cancel()
        fx.ticker = nil
    end
end

local PaintReel, PlaceReel

local function EnsureReel(fx)
    if fx.ticker or not (C_Timer and type(C_Timer.NewTicker) == "function") then
        return
    end
    fx.ticker = C_Timer.NewTicker(0.02, function()
        local target = fx.revealTarget or 0
        local reveal = fx.reveal or 0
        if reveal < target then
            fx.reveal = math.min(target, reveal + 0.04)
        elseif reveal > target then
            fx.reveal = math.max(target, reveal - 0.04)
        end
        LayoutDoors(fx)
        if (fx.reveal or 0) > 0 and fx.owner and fx.owner.bgvText then
            local text = fx.owner.bgvText
            if text.bgvFadeTarget ~= 0 then
                FadeCaption(fx.owner, 0)
            elseif text:GetAlpha() > 0.02 and not (text.bgvFade and text.bgvFade:IsPlaying()) then
                text:SetAlpha(0)
            end
        end
        if type(fx.icons) == "table" and #fx.icons > 0 then
            fx.offset = (fx.offset or 0) - 2
            if fx.offset <= -CASE_STRIDE then
                fx.offset = fx.offset + CASE_STRIDE
                fx.cursor = (fx.cursor or 1) + 1
                PaintReel(fx)
            end
            PlaceReel(fx)
        end
        if fx.revealTarget == 0 and fx.reveal <= 0 then
            StopReel(fx)
            fx.reelReady = nil
            fx:Hide()
            LayoutDoors(fx)
            FadeCaption(fx.owner, 1)
        end
    end)
end

function PlaceReel(fx)
    fx.reel:SetWidth(CASE_STRIDE * CASE_SLOTS)
    fx.reel:ClearAllPoints()
    fx.reel:SetPoint("TOPLEFT", fx, "TOPLEFT", fx.offset or 0, 0)
    fx.reel:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", fx.offset or 0, 0)
end

local function HideDefaultShine(activityFrame)
    if not activityFrame or not activityFrame.IsShown or not activityFrame:IsShown() then
        return
    end
    if activityFrame.CompletedActivityFlipbook then
        activityFrame.CompletedActivityFlipbook:Hide()
    end
    if activityFrame.CompletedActivityAnim then
        activityFrame.CompletedActivityAnim:Stop()
    end
    if activityFrame.UncollectedGlow then
        activityFrame.UncollectedGlow:Hide()
        if activityFrame.UncollectedGlow.FadeAnim then
            activityFrame.UncollectedGlow.FadeAnim:Stop()
        end
    end
    if activityFrame.ItemGlow then
        activityFrame.ItemGlow:Hide()
    end
    if activityFrame.RewardGenerated then
        activityFrame.RewardGenerated:Hide()
    end

    local effect = activityFrame.activeEffect
    activityFrame.activeEffect = nil
    activityFrame.activeEffectInfo = nil
    if effect and effect.CancelEffect then
        effect:CancelEffect()
    end

    local parent = activityFrame:GetParent()
    local scene = parent and parent.ModelScene
    if not scene and WeeklyRewardsFrame then
        scene = WeeklyRewardsFrame.ModelScene
    end
    if scene then
        scene:SetAlpha(0)
        scene:Hide()
    end
end

function PaintReel(fx)
    local icons = fx.icons
    if type(icons) ~= "table" or #icons == 0 then
        return
    end
    for index, cell in ipairs(fx.cells) do
        local entry = icons[((fx.cursor + index - 2) % #icons) + 1]
        local itemID = type(entry) == "table" and entry.itemID or nil
        local icon = type(entry) == "table" and entry.icon or entry
        cell.icon:SetTexture(icon)
        cell.icon:SetSize(CASE_ICON, CASE_ICON)
        local tier = itemID and BGV.Bis and BGV.Bis.Tier(itemID) or nil
        local color = tier and TIER_BACK[tier] or nil
        if color then
            ColorTexture(cell.back, color[1], color[2], color[3], 0.92)
            cell.back:Show()
        else
            cell.back:Hide()
        end
    end
end

local function StopFX(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    if fx.ticker then
        fx.ticker:Cancel()
        fx.ticker = nil
    end
    fx.reveal = 0
    fx.revealTarget = 0
    if fx.open then
        fx.open:Stop()
    end
    if fx.close then
        fx.close:Stop()
    end
    fx:Hide()
    if fx.topDoor then
        fx.topDoor:Hide()
    end
    if fx.bottomDoor then
        fx.bottomDoor:Hide()
    end
    FadeCaption(activityFrame, 1)
end

local function FitCase(activityFrame)
    local fx = activityFrame.bgvFX
    if not fx then
        return
    end
    fx:ClearAllPoints()
    fx:SetPoint("TOPLEFT", activityFrame, "TOPLEFT", 0, 0)
    fx:SetPoint("BOTTOMRIGHT", activityFrame, "BOTTOMRIGHT", 0, 0)
    local atlas = "evergreen-weeklyrewards-reward-unlocked"
    local bg = activityFrame.Background
    if bg and type(bg.GetAtlas) == "function" then
        local current = bg:GetAtlas()
        if type(current) == "string" and current ~= "" then
            atlas = current
        end
    end
    for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
        if gate and gate.face and type(gate.face.SetAtlas) == "function" then
            gate.face:SetAtlas(atlas)
        end
    end
end

local function PlaceCase(activityFrame)
    local fx = activityFrame.bgvFX
    if not fx then
        return
    end
    FitCase(activityFrame)
    local level = activityFrame:GetFrameLevel() + 2
    if activityFrame.ItemFrame and type(activityFrame.ItemFrame.GetFrameLevel) == "function" then
        level = math.max(level, activityFrame.ItemFrame:GetFrameLevel() + 1)
    end
    fx:SetFrameLevel(level)
    if fx.reel then
        fx.reel:SetFrameLevel(level)
    end
    if fx.topDoor then
        fx.topDoor:SetFrameLevel(level + 6)
        fx.bottomDoor:SetFrameLevel(level + 6)
    end
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(level + 8)
    end
    if activityFrame.bgvHit then
        activityFrame.bgvHit:SetFrameLevel(level + 10)
    end
end

local function StartCase(activityFrame)
    if not activityFrame or not activityFrame.IsShown or not activityFrame:IsShown() then
        return
    end
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    local icons = fx.icons

    PlaceCase(activityFrame)
    if fx.open then
        fx.open:Stop()
    end
    if fx.close then
        fx.close:Stop()
    end
    fx.revealTarget = 1
    if type(icons) == "table" and #icons > 0 and not fx.reelReady then
        fx.cursor = math.random(#icons)
        fx.offset = 0
        PaintReel(fx)
        PlaceReel(fx)
        fx.reelReady = true
    end
    fx:Show()
    LayoutDoors(fx)
    EnsureReel(fx)
    FadeCaption(activityFrame, 0)
end

local function CloseCase(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx or not fx:IsShown() then
        return
    end
    if fx.open then
        fx.open:Stop()
    end
    if fx.close then
        fx.close:Stop()
    end
    fx.revealTarget = 0
    EnsureReel(fx)
end

local function UpdateFX(activityFrame, slot, fromEnter)
    EnsureFX(activityFrame)
    local fx = activityFrame.bgvFX
    local icons = BGV.Rewards.PossibleIcons(slot)
    if fx.iconKey ~= icons then
        fx.reelReady = nil
    end
    fx.icons = icons
    fx.iconKey = icons
    local hovering = fromEnter or (activityFrame.bgvHit and activityFrame.bgvHit:IsMouseOver())
    if hovering and slot and slot.unlocked then
        StartCase(activityFrame)
        return
    end
    if slot and slot.unlocked then
        if not fx.ticker and (fx.reveal or 0) <= 0 then
            fx.reveal = 0
            fx.revealTarget = 0
            PlaceCase(activityFrame)
            LayoutDoors(fx)
            fx:Hide()
        end
    else
        StopFX(activityFrame)
    end
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
        activityFrame.bgvHoverGen = (activityFrame.bgvHoverGen or 0) + 1
        BGV.Tooltip.ShowStandalone(activityFrame)
        if activityFrame.bgvSlot then
            UpdateFX(activityFrame, activityFrame.bgvSlot, true)
        end
    end)
    hit:SetScript("OnLeave", function()
        local owner = GameTooltip and GameTooltip:GetOwner()
        if owner == hit or owner == activityFrame then
            GameTooltip:Hide()
        end
        local generation = activityFrame.bgvHoverGen or 0
        if not (C_Timer and type(C_Timer.After) == "function") then
            CloseCase(activityFrame)
            return
        end
        C_Timer.After(0.05, function()
            if not activityFrame:IsShown() or (activityFrame.bgvHoverGen or 0) ~= generation then
                return
            end
            if hit:IsMouseOver() or activityFrame:IsMouseOver() then
                return
            end
            CloseCase(activityFrame)
        end)
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

    if not activityFrame.bgvText then
        local text = CreateFrame("Frame", nil, activityFrame)
        text:SetAllPoints(activityFrame)
        text:EnableMouse(false)
        activityFrame.bgvText = text
    end
    activityFrame.bgvProgress:SetParent(activityFrame.bgvText)
    activityFrame.bgvReward:SetParent(activityFrame.bgvText)

    LayoutLines(activityFrame)
    EnsureHit(activityFrame)
    if activityFrame.SetClipsChildren then
        activityFrame:SetClipsChildren(false)
    end

    local level = activityFrame:GetFrameLevel() + 4
    if activityFrame.bgvFX then
        activityFrame.bgvFX:SetFrameLevel(activityFrame:GetFrameLevel() + 1)
    end
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(activityFrame:GetFrameLevel() + 3)
        level = activityFrame.bgvText:GetFrameLevel() + 2
    end
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
    StopFX(activityFrame)
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
        if info.icon and not Utils.IsSecret(info.icon) then
            slot.rewardIcon = info.icon
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
    UpdateFX(activityFrame, slot)
end

function UI.Apply(activityFrame, slot, playOpen)
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
    HideDefaultShine(activityFrame)

    local rewardText = BGV.GreatVault.DetailText(slot)
    if rewardText then
        activityFrame.bgvReward:SetText(rewardText)
        activityFrame.bgvReward:Show()
    else
        activityFrame.bgvReward:Hide()
    end
    LayoutLines(activityFrame)
    UpdateFX(activityFrame, slot)

    if Utils.IsUsableNumber(slot.itemLevel) or type(slot.itemQuality) == "string" or slot.rewardIcon then
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

    local playOpen = not weeklyRewardsFrame.bgvOpenPlayed
    weeklyRewardsFrame.bgvOpenPlayed = true
    BGV.GreatVault.Invalidate()
    local snapshot = BGV.GreatVault.GetSnapshot()
    local seen = {}

    for _, slot in ipairs(snapshot) do
        local activityFrame = weeklyRewardsFrame:GetActivityFrame(slot.type, slot.index)
        if activityFrame then
            seen[activityFrame] = true
            UI.Apply(activityFrame, slot, playOpen)
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
    if not weeklyRewardsFrame or not weeklyRewardsFrame.IsShown or not weeklyRewardsFrame:IsShown() then
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

    if type(WeeklyRewardsMixin.OnHide) == "function" then
        hooksecurefunc(WeeklyRewardsMixin, "OnHide", function(self)
            self.bgvOpenPlayed = nil
            if type(self.Activities) == "table" then
                for _, activityFrame in ipairs(self.Activities) do
                    StopFX(activityFrame)
                end
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetActiveEffect) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "SetActiveEffect", function(self)
            if self.bgvSlot and self:IsShown() then
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.Refresh) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "Refresh", function(self)
            if self.bgvSlot and self:IsShown() then
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetProgressText) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "SetProgressText", function(self)
            if self.bgvSlot and self:IsShown() then
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
            StopFX(self)
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
