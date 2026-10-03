local _, BGV = ...

BGV.UI = {}

local UI = BGV.UI
local Utils = BGV.Utils
local Case = BGV.Case

-- Hooks on Blizzard's vault: an error in one of ours is noted (Utils.Protect), never passed back to
-- the Blizzard code that called it.
local function Hook(target, method, fn)
    hooksecurefunc(target, method, Utils.Protect("vault hook", fn))
end

local function HookScript(frame, script, fn)
    frame:HookScript(script, Utils.Protect("vault hook", fn))
end

local function AnimationsDisabled()
    return BetterGreatVaultDB and BetterGreatVaultDB.disableAnimations == true
end

local function OpenLootTableOnClick()
    return not BetterGreatVaultDB or BetterGreatVaultDB.openLootTable ~= false
end

-- The addon's outlined small font, sized by the text size setting (Utils.ApplyFontSize).
local function ApplyFont(fontString)
    fontString:SetFontObject(Utils.Font("Vault"))
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

local PUMP_STALL_DELAY = 0.25
-- Retries cover the ~10s Rewards may wait on item data before settling a list.
local PUMP_STALL_RETRIES = 40

local function PaintReward(activityFrame)
    local reward = activityFrame and activityFrame.bgvReward
    if not reward then
        return
    end
    reward:SetTextColor(1, 0.82, 0)
    local text = reward.GetText and reward:GetText() or nil
    if type(text) == "string" and text ~= "" then
        reward:SetText(text)
        reward:SetTextColor(1, 0.82, 0)
    end
end

function UI.RepaintAccent()
    local frame = WeeklyRewardsFrame
    local activities = frame and frame.Activities
    if type(activities) ~= "table" then
        return
    end
    for _, activityFrame in ipairs(activities) do
        PaintReward(activityFrame)
        Case.RepaintAccent(activityFrame)
    end
end

local function BuryShownRegion(region)
    if not region then
        return
    end
    if not region.bgvBuryHook and type(hooksecurefunc) == "function" then
        region.bgvBuryHook = true
        local function Force(self)
            local parent = self.GetParent and self:GetParent()
            while parent and not parent.bgvSlot and parent.GetParent do
                parent = parent:GetParent()
            end
            if not parent or not parent.bgvSlot or self.bgvForcing then
                return
            end
            self.bgvForcing = true
            self:SetAlpha(0)
            self:Hide()
            self.bgvForcing = false
        end
        Hook(region, "Show", Force)
        Hook(region, "SetAlpha", function(self, alpha)
            if alpha ~= 0 then
                Force(self)
            end
        end)
    end
    region:SetAlpha(0)
    region:Hide()
end

local function KillAnim(anim)
    if not anim then
        return
    end
    if anim.HookScript and not anim.bgvBuryHook then
        anim.bgvBuryHook = true
        HookScript(anim, "OnPlay", function(self)
            local owner = self.GetParent and self:GetParent()
            while owner and not owner.bgvSlot and owner.GetParent do
                owner = owner:GetParent()
            end
            if owner and owner.bgvSlot then
                self:Stop()
            end
        end)
    end
    anim:Stop()
end

local function HideDefaultShine(activityFrame)
    if not activityFrame then
        return
    end
    BuryShownRegion(activityFrame.CompletedIcon)
    BuryShownRegion(activityFrame.CompletedActivityFlipbook)
    BuryShownRegion(activityFrame.ItemGlow)
    KillAnim(activityFrame.CompletedActivityAnim)
    KillAnim(activityFrame.SheenAnim)
    if activityFrame.UncollectedGlow then
        KillAnim(activityFrame.UncollectedGlow.FadeAnim)
        BuryShownRegion(activityFrame.UncollectedGlow)
    end
    if not activityFrame.bgvGlowRegionsSealed and type(activityFrame.GetRegions) == "function" then
        activityFrame.bgvGlowRegionsSealed = true
        for _, region in ipairs({ activityFrame:GetRegions() }) do
            local atlas = region.GetAtlas and region:GetAtlas()
            if type(atlas) == "string" then
                local name = atlas:lower()
                if name:find("backglow", 1, true) or name:find("checkmark", 1, true) or name:find("flipbook", 1, true) then
                    BuryShownRegion(region)
                end
            end
        end
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

local function HideClosedGates(activityFrame)
    local closed = activityFrame and activityFrame.bgvClosed
    if closed then
        closed:Hide()
    end
end

local function EnsureClosedGates(activityFrame)
    if activityFrame.bgvClosed then
        return
    end

    local closed = CreateFrame("Frame", nil, activityFrame)
    closed:SetPoint("TOPLEFT", activityFrame, "TOPLEFT", 0, 0)
    closed:SetPoint("BOTTOMRIGHT", activityFrame, "BOTTOMRIGHT", 0, 0)
    closed:EnableMouse(false)
    closed:SetFrameLevel(activityFrame:GetFrameLevel() + 2)

    local function MakeDoor(anchor)
        local door = CreateFrame("Frame", nil, closed)
        door:EnableMouse(false)
        if door.SetClipsChildren then
            door:SetClipsChildren(true)
        end
        if anchor == "TOP" then
            door:SetPoint("TOPLEFT", closed, "TOPLEFT", 0, 0)
            door:SetPoint("TOPRIGHT", closed, "TOPRIGHT", 0, 0)
        else
            door:SetPoint("BOTTOMLEFT", closed, "BOTTOMLEFT", 0, 0)
            door:SetPoint("BOTTOMRIGHT", closed, "BOTTOMRIGHT", 0, 0)
        end
        local face = door:CreateTexture(nil, "ARTWORK")
        face:SetPoint("TOPLEFT", closed, "TOPLEFT", 0, 0)
        face:SetPoint("BOTTOMRIGHT", closed, "BOTTOMRIGHT", 0, 0)
        face:SetAlpha(1)
        if face.SetAtlas then
            face:SetAtlas("evergreen-weeklyrewards-reward-unlocked")
        end
        door.face = face
        return door
    end

    closed.topDoor = MakeDoor("TOP")
    closed.bottomDoor = MakeDoor("BOTTOM")
    closed:Hide()
    activityFrame.bgvClosed = closed
end

local function ShowClosedGates(activityFrame)
    Case.Stop(activityFrame)
    Case.RaiseAboveGlow(activityFrame)
    EnsureClosedGates(activityFrame)
    local closed = activityFrame.bgvClosed
    local slot = activityFrame:GetHeight()
    if not slot or slot < 4 then
        slot = 126
    end
    local half = slot * 0.5
    local atlas = Case.FaceAtlas(activityFrame)
    local level = activityFrame:GetFrameLevel() + 2
    if activityFrame.ItemFrame and type(activityFrame.ItemFrame.GetFrameLevel) == "function" then
        level = math.max(level, activityFrame.ItemFrame:GetFrameLevel() + 1)
    end
    level = level + 8
    for _, door in ipairs({ closed.topDoor, closed.bottomDoor }) do
        door:SetHeight(half)
        if door.face and type(door.face.SetAtlas) == "function" then
            door.face:SetAtlas(atlas)
        end
        door:Show()
    end
    closed:SetFrameLevel(level)
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(level + 2)
        activityFrame.bgvText:SetAlpha(1)
    end
    closed:Show()
end

local function UpdateFX(activityFrame, slot, fromEnter)
    if AnimationsDisabled() then
        if slot and slot.unlocked then
            ShowClosedGates(activityFrame)
        else
            HideClosedGates(activityFrame)
            Case.Stop(activityFrame)
        end
        return
    end
    HideClosedGates(activityFrame)
    local fx = Case.Ensure(activityFrame)
    local hovering = fromEnter or (activityFrame.bgvHit and activityFrame.bgvHit:IsMouseOver())
    if hovering and slot and slot.unlocked and Case.VaultIsOpen() then
        local icons, pending = BGV.Rewards.PossibleIcons(slot)
        if fx.iconKey ~= icons or (type(icons) == "table" and #icons ~= fx.iconCount) then
            fx.reelReady = nil
        end
        fx.icons = icons
        fx.iconKey = icons
        fx.iconCount = type(icons) == "table" and #icons or 0
        fx.iconsPending = pending == true
        fx.refreshClock = 0
        Case.Open(activityFrame)
        if not fx.reelReady then
            Case.PaintReel(fx)
        end
        return
    end
    if slot and slot.unlocked then
        if not Case.IsAnimating(activityFrame) then
            Case.Rest(activityFrame)
        end
    else
        Case.Stop(activityFrame)
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
            Case.Close(activityFrame)
            return
        end
        C_Timer.After(0.05, function()
            if not activityFrame:IsShown() or (activityFrame.bgvHoverGen or 0) ~= generation then
                return
            end
            if Case.PointerOnSlot(activityFrame) then
                return
            end
            Case.Close(activityFrame)
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
        if button == "LeftButton" and not IsModifiedClick() and OpenLootTableOnClick() and activityFrame.bgvSlot and activityFrame.bgvSlot.unlocked and BGV.LootTable and type(BGV.LootTable.ShowSlot) == "function" then
            BGV.LootTable.ShowSlot(activityFrame.bgvSlot)
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
        PaintReward({ bgvReward = reward })

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

local function BuryDefaultRegion(region)
    if not region then
        return
    end
    if region.bgvBuryHook then
        region:SetAlpha(0)
        return
    end
    region.bgvBuryHook = true
    local function Force()
        local parent = region.GetParent and region:GetParent()
        if not parent or not parent.bgvSlot or region.bgvForcing then
            return
        end
        region.bgvForcing = true
        region:SetAlpha(0)
        region.bgvForcing = false
    end
    if region.HookScript then
        HookScript(region, "OnShow", Force)
    elseif type(hooksecurefunc) == "function" then
        Hook(region, "Show", Force)
    end
    if type(hooksecurefunc) == "function" then
        Hook(region, "SetAlpha", function(_, alpha)
            if alpha ~= 0 then
                Force()
            end
        end)
    end
    Force()
end

local function HideDefaultCaption(activityFrame)
    if activityFrame.Threshold then
        BuryDefaultRegion(activityFrame.Threshold)
        activityFrame.Threshold:Hide()
    end
    if activityFrame.Progress then
        BuryDefaultRegion(activityFrame.Progress)
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

-- EllesmereUI's Great Vault skin gives each slot a square card (frames of the slot marked with
-- _euiTileBg and _euiDarkOverlay, its border inside) and a progress bar along the bottom (marked
-- with _euiFill and _euiTrack), green on a complete slot. On the addon's unlocked slots both
-- showed around the gates (at their rounded corners and bottom edge), so there they're made
-- transparent, and they're back wherever the vault is Blizzard's again. The skin shows its card
-- on every refresh but never sets the alpha of either, so this holds.
local function IsSkinPiece(frame)
    return (frame._euiFill and frame._euiTrack) or frame._euiTileBg or frame._euiDarkOverlay
end

local function SyncSkin(activityFrame)
    if not activityFrame or type(activityFrame.GetChildren) ~= "function" then
        return
    end
    local slot = activityFrame.bgvSlot
    local alpha = (slot and slot.unlocked) and 0 or 1
    for _, child in ipairs({ activityFrame:GetChildren() }) do
        if IsSkinPiece(child) and child:GetAlpha() ~= alpha then
            child:SetAlpha(alpha)
        end
    end
end

-- The skin makes its card and bar a frame after the vault first shows, so the slots are synced
-- again once that has run.
local function SyncSkinSoon(weeklyRewardsFrame)
    if not weeklyRewardsFrame or weeklyRewardsFrame.bgvSkinQueued or not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    weeklyRewardsFrame.bgvSkinQueued = true
    C_Timer.After(0, function()
        C_Timer.After(0, function()
            weeklyRewardsFrame.bgvSkinQueued = nil
            for _, activityFrame in ipairs(type(weeklyRewardsFrame.Activities) == "table" and weeklyRewardsFrame.Activities or {}) do
                SyncSkin(activityFrame)
            end
        end)
    end)
end

local function ProgressWeek()
    return not (BGV.Rewards and BGV.Rewards.ShowingWeeklyProgress) or BGV.Rewards.ShowingWeeklyProgress()
end

local function EnsureSpecButton(weeklyRewardsFrame)
    local button = weeklyRewardsFrame.bgvSpecButton
    if button then
        return button
    end
    button = Utils.CreateLootSpecButton(weeklyRewardsFrame, true)
    -- In line with the rows' labels (Blizzard's RaidFrame and the rest sit at x 68), clear of the
    -- vault border's corner bracket, which draws over everything in the frame's top-left.
    button:SetPoint("TOPLEFT", weeklyRewardsFrame, "TOPLEFT", 68, -34)
    button:SetFrameLevel(weeklyRewardsFrame:GetFrameLevel() + 20)
    weeklyRewardsFrame.bgvSpecButton = button
    return button
end

local function HideSpecButton(weeklyRewardsFrame)
    local button = weeklyRewardsFrame and weeklyRewardsFrame.bgvSpecButton
    if button then
        button:Hide()
    end
end

local function RefreshSpecButton(weeklyRewardsFrame)
    if not Utils.LootSpecButtonEnabled() then
        HideSpecButton(weeklyRewardsFrame)
        return
    end
    Utils.RefreshLootSpecButton(EnsureSpecButton(weeklyRewardsFrame))
end

local function RestoreScene()
    local scene = WeeklyRewardsFrame and WeeklyRewardsFrame.ModelScene
    if scene then
        scene:SetAlpha(1)
        scene:Show()
    end
end

local function ReleaseRegion(region)
    if not region then
        return
    end
    region.bgvForcing = true
    region:SetAlpha(1)
    if region.Show then
        region:Show()
    end
    region.bgvForcing = false
end

local function RestoreVanilla(activityFrame)
    if not activityFrame then
        return
    end
    activityFrame.bgvSlot = nil
    activityFrame.bgvToken = (activityFrame.bgvToken or 0) + 1
    if activityFrame.bgvProgress then
        activityFrame.bgvProgress:Hide()
        activityFrame.bgvReward:Hide()
    end
    if activityFrame.bgvText then
        activityFrame.bgvText:Hide()
    end
    if activityFrame.bgvHit then
        activityFrame.bgvHit:Hide()
    end
    Case.Stop(activityFrame)
    HideClosedGates(activityFrame)
    ShowDefaultCaption(activityFrame)
    if activityFrame.Threshold then
        activityFrame.Threshold:SetAlpha(1)
    end
    if activityFrame.Progress then
        activityFrame.Progress:SetAlpha(1)
    end
    ReleaseRegion(activityFrame.CompletedIcon)
    ReleaseRegion(activityFrame.CompletedActivityFlipbook)
    ReleaseRegion(activityFrame.ItemGlow)
    ReleaseRegion(activityFrame.UncollectedGlow)
    if activityFrame.RewardGenerated then
        activityFrame.RewardGenerated:Hide()
    end
    if activityFrame.bgvBaseLevel then
        activityFrame:SetFrameLevel(activityFrame.bgvBaseLevel)
    end
    SyncSkin(activityFrame)
end

local function RestoreVault(weeklyRewardsFrame)
    RestoreScene()
    HideSpecButton(weeklyRewardsFrame)
    local frames = weeklyRewardsFrame and weeklyRewardsFrame.Activities
    if type(frames) ~= "table" then
        return
    end
    for _, activityFrame in ipairs(frames) do
        RestoreVanilla(activityFrame)
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
    Case.Stop(activityFrame)
    HideClosedGates(activityFrame)
    ShowDefaultCaption(activityFrame)
    SyncSkin(activityFrame)
end

local function ShowReward(activityFrame, slot, info)
    if type(info) == "table" then
        if Utils.IsUsableNumber(info.itemLevel) then
            slot.itemLevel = info.itemLevel
        end
        if type(info.qualityName) == "string" and info.qualityName ~= "" then
            slot.itemQuality = info.qualityName
        end
        if Utils.IsUsableNumber(info.quality) then
            slot.quality = info.quality
        end
        if type(info.link) == "string" and info.link ~= "" then
            slot.rewardLink = info.link
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
        PaintReward(activityFrame)
        activityFrame.bgvReward:Show()
    else
        activityFrame.bgvReward:Hide()
    end
    LayoutLines(activityFrame)
    UpdateFX(activityFrame, slot)
end

function UI.Apply(activityFrame, slot)
    if not activityFrame or type(slot) ~= "table" then
        return
    end

    EnsureLines(activityFrame)
    Case.RaiseAboveGlow(activityFrame)
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
        PaintReward(activityFrame)
        activityFrame.bgvReward:Show()
    else
        activityFrame.bgvReward:Hide()
    end
    LayoutLines(activityFrame)
    UpdateFX(activityFrame, slot)
    SyncSkin(activityFrame)

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
    if not ProgressWeek() then
        weeklyRewardsFrame.bgvShellReady = nil
        RestoreVault(weeklyRewardsFrame)
        return
    end

    weeklyRewardsFrame.bgvShellReady = true
    RefreshSpecButton(weeklyRewardsFrame)
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
    if not weeklyRewardsFrame or not weeklyRewardsFrame.IsShown or not weeklyRewardsFrame:IsShown() then
        return
    end

    local ok, err = pcall(UI.Update, weeklyRewardsFrame)
    if not ok then
        Utils.NoteError("vault overlay", err)
    end
end

local shellApplying = false

function UI.Prepare()
    local weeklyRewardsFrame = WeeklyRewardsFrame
    if not weeklyRewardsFrame or shellApplying then
        return
    end
    shellApplying = true
    local ok, err = pcall(function()
        if type(weeklyRewardsFrame.Refresh) == "function" then
            weeklyRewardsFrame:Refresh()
        end
        UI.Update(weeklyRewardsFrame)
    end)
    shellApplying = false
    if not ok then
        Utils.NoteError("vault overlay", err)
    end
end

function UI.ScheduleContent(weeklyRewardsFrame)
    if not ProgressWeek() then
        return
    end
    if not weeklyRewardsFrame or not Case.VaultIsOpen() or weeklyRewardsFrame.bgvContentQueued then
        return
    end
    weeklyRewardsFrame.bgvContentQueued = true
    BGV.GreatVault.RequestRunData()
    if not (C_Timer and type(C_Timer.After) == "function") then
        weeklyRewardsFrame.bgvContentQueued = nil
        return
    end
    C_Timer.After(0, function()
        weeklyRewardsFrame.bgvContentQueued = nil
        if not Case.VaultIsOpen() then
            return
        end
        if weeklyRewardsFrame.bgvPumping then
            return
        end
        weeklyRewardsFrame.bgvPumping = true
        -- A restart (e.g. after a loot spec change) supersedes any run still scheduled.
        local generation = (weeklyRewardsFrame.bgvPumpGen or 0) + 1
        weeklyRewardsFrame.bgvPumpGen = generation
        weeklyRewardsFrame.bgvPumpStalls = 0
        local index = weeklyRewardsFrame.bgvPumpIndex or 1
        local function Step()
            if weeklyRewardsFrame.bgvPumpGen ~= generation then
                return
            end
            if not Case.VaultIsOpen() then
                weeklyRewardsFrame.bgvPumping = nil
                return
            end
            local ok, snapshot = pcall(BGV.GreatVault.GetSnapshot)
            if not ok or type(snapshot) ~= "table" then
                weeklyRewardsFrame.bgvPumping = nil
                return
            end
            while index <= #snapshot do
                local slot = snapshot[index]
                if slot.unlocked and not AnimationsDisabled() then
                    break
                end
                index = index + 1
            end
            weeklyRewardsFrame.bgvPumpIndex = index
            if index > #snapshot then
                weeklyRewardsFrame.bgvPumping = nil
                weeklyRewardsFrame.bgvPumpIndex = nil
                weeklyRewardsFrame.bgvPumpCount = nil
                return
            end
            local icons, pending = BGV.Rewards.PossibleIcons(snapshot[index])
            local count = type(icons) == "table" and #icons or 0
            if pending and count <= (weeklyRewardsFrame.bgvPumpCount or -1) then
                -- No progress this pass. Loot often arrives without a journal event, so retry on a
                -- short timer for a few seconds before falling back to waiting for one.
                weeklyRewardsFrame.bgvPumpStalls = (weeklyRewardsFrame.bgvPumpStalls or 0) + 1
                if weeklyRewardsFrame.bgvPumpStalls <= PUMP_STALL_RETRIES then
                    C_Timer.After(PUMP_STALL_DELAY, Step)
                    return
                end
                weeklyRewardsFrame.bgvPumping = nil
                weeklyRewardsFrame.bgvPumpWait = true
                return
            end
            weeklyRewardsFrame.bgvPumpStalls = 0
            if pending then
                weeklyRewardsFrame.bgvPumpCount = count
            else
                index = index + 1
                weeklyRewardsFrame.bgvPumpIndex = index
                weeklyRewardsFrame.bgvPumpCount = nil
            end
            if index <= #snapshot then
                C_Timer.After(0.05, Step)
            else
                weeklyRewardsFrame.bgvPumping = nil
                weeklyRewardsFrame.bgvPumpIndex = nil
            end
        end
        C_Timer.After(0.05, Step)
    end)
end

local function CloseOpenGates(weeklyRewardsFrame)
    if BGV.Faces then
        BGV.Faces.Stop()
    end
    if not ProgressWeek() then
        RestoreVault(weeklyRewardsFrame)
        return
    end
    local frames = weeklyRewardsFrame and weeklyRewardsFrame.Activities
    if type(frames) ~= "table" then
        return
    end
    for _, activityFrame in ipairs(frames) do
        activityFrame.bgvHoverGen = (activityFrame.bgvHoverGen or 0) + 1
        HideDefaultShine(activityFrame)
        Case.Shut(activityFrame)
    end
end

local function KeepShell(weeklyRewardsFrame)
    if not ProgressWeek() then
        RestoreVault(weeklyRewardsFrame)
        return
    end
    local frames = weeklyRewardsFrame and weeklyRewardsFrame.Activities
    if type(frames) ~= "table" then
        return
    end
    for _, activityFrame in ipairs(frames) do
        if activityFrame.bgvSlot then
            HideDefaultCaption(activityFrame)
            HideDefaultShine(activityFrame)
        end
    end
end

function UI.Hook()
    if UI.hooked or type(WeeklyRewardsMixin) ~= "table" or type(hooksecurefunc) ~= "function" then
        return false
    end

    if type(WeeklyRewardsMixin.Refresh) == "function" then
        Hook(WeeklyRewardsMixin, "Refresh", function(self)
            if not ProgressWeek() then
                RestoreVault(self)
                return
            end
            if shellApplying or not self:IsShown() then
                return
            end
            SyncSkinSoon(self)
            if self.bgvShellReady then
                KeepShell(self)
                return
            end
            UI.SafeUpdate(self)
            UI.ScheduleContent(self)
        end)
    end

    if type(WeeklyRewardsMixin.OnShow) == "function" then
        Hook(WeeklyRewardsMixin, "OnShow", function(self)
            if not ProgressWeek() then
                RestoreVault(self)
                return
            end
            SyncSkinSoon(self)
            if self.bgvShellReady then
                KeepShell(self)
                return
            end
            UI.SafeUpdate(self)
            UI.ScheduleContent(self)
        end)
    end

    if type(WeeklyRewardsMixin.OnHide) == "function" then
        Hook(WeeklyRewardsMixin, "OnHide", function(self)
            CloseOpenGates(self)
        end)
    end

    if WeeklyRewardsFrame and not WeeklyRewardsFrame.bgvHideHook then
        WeeklyRewardsFrame.bgvHideHook = true
        HookScript(WeeklyRewardsFrame, "OnHide", function(self)
            CloseOpenGates(self)
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetActiveEffect) == "function" then
        Hook(WeeklyRewardsActivityMixin, "SetActiveEffect", function(self)
            if self.bgvSlot then
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.Refresh) == "function" then
        Hook(WeeklyRewardsActivityMixin, "Refresh", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetProgressText) == "function" then
        Hook(WeeklyRewardsActivityMixin, "SetProgressText", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.OnShow) == "function" then
        Hook(WeeklyRewardsActivityMixin, "OnShow", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
                HideDefaultShine(self)
            end
        end)
    end

    -- Pointing at Collect saddens the gates (Faces.lua).
    if BGV.Faces and WeeklyRewardsFrame then
        BGV.Faces.Hook(WeeklyRewardsFrame)
    end

    if WeeklyRewardsFrame and WeeklyRewardsFrame.HookScript and not WeeklyRewardsFrame.bgvAccentShow then
        WeeklyRewardsFrame.bgvAccentShow = true
        HookScript(WeeklyRewardsFrame, "OnShow", function()
            if not ProgressWeek() then
                return
            end
            if UI.RepaintAccent then
                UI.RepaintAccent()
            end
        end)
    end

    UI.hooked = true
    return true
end

function UI.RefreshOpenFrame()
    if not ProgressWeek() then
        if WeeklyRewardsFrame then
            RestoreVault(WeeklyRewardsFrame)
        end
        return
    end
    if UI.RepaintAccent then
        UI.RepaintAccent()
    end
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
        UI.SafeUpdate(WeeklyRewardsFrame)
    end
end
