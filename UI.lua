local _, BGV = ...

BGV.UI = {}

local UI = BGV.UI
local Utils = BGV.Utils
local Case = BGV.Case
local L = BGV.L

-- Hooks on Blizzard's vault: an error in one of ours is noted (Utils.Protect), never passed back to
-- the Blizzard code that called it.
local function Hook(target, method, fn)
    hooksecurefunc(target, method, Utils.Protect("vault hook", fn))
end

local function HookScript(frame, script, fn)
    frame:HookScript(script, Utils.Protect("vault hook", fn))
end

local AnimationsDisabled = Utils.AnimationsOff

local function OpenLootTableOnClick()
    return not BetterGreatVaultDB or BetterGreatVaultDB.openLootTable ~= false
end

-- The vault shows this week's progress, not rewards rolled: the only time the addon lays the slots
-- out itself.
local ProgressWeek = Utils.ProgressWeek

-- Whether the addon holds a slot's own art and text down: while it shows the slot itself (the
-- progress week's slots; at the vault, the rewards' cases). Otherwise Blizzard's refresh decides,
-- even before the addon has let go of the slot (RestoreVanilla).
local function Holds(activityFrame)
    return activityFrame.bgvClaim ~= nil or (activityFrame.bgvSlot ~= nil and ProgressWeek())
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

-- The middle of the band above a locked slot's keyhole, below the slot's top: the keyhole starts
-- about 50 below the top of Blizzard's 126-high slot, and the art's edge takes the first 8.
local LOCKED_BAND_MIDDLE = 28

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

    progress:ClearAllPoints()
    local slot = activityFrame.bgvSlot
    if type(slot) == "table" and not slot.unlocked then
        -- A locked slot's art has its keyhole in the middle: the text goes in the band above it,
        -- where Blizzard keeps its own (its Threshold sits 16 below the top).
        local top = math.min(-4, total / 2 - LOCKED_BAND_MIDDLE)
        progress:SetPoint("TOPLEFT", activityFrame, "TOPLEFT", 10, top)
        progress:SetPoint("TOPRIGHT", activityFrame, "TOPRIGHT", -10, top)
    else
        local top = total / 2
        progress:SetPoint("TOPLEFT", activityFrame, "LEFT", 10, top)
        progress:SetPoint("TOPRIGHT", activityFrame, "RIGHT", -10, top)
    end
    reward:ClearAllPoints()
    reward:SetPoint("TOPLEFT", progress, "BOTTOMLEFT", 0, -2)
    reward:SetPoint("TOPRIGHT", progress, "BOTTOMRIGHT", 0, -2)
end

local PUMP_STALL_DELAY = 0.25
-- Retries cover the ~10s Rewards may wait on item data before settling a list.
local PUMP_STALL_RETRIES = 40

local function BuryShownRegion(region)
    if not region then
        return
    end
    if not region.bgvBuryHook and type(hooksecurefunc) == "function" then
        region.bgvBuryHook = true
        local function Force(self)
            local parent = self.GetParent and self:GetParent()
            while parent and not (parent.bgvSlot or parent.bgvClaim) and parent.GetParent do
                parent = parent:GetParent()
            end
            if not parent or not Holds(parent) or self.bgvForcing then
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
            while owner and not (owner.bgvSlot or owner.bgvClaim) and owner.GetParent do
                owner = owner:GetParent()
            end
            if owner and Holds(owner) then
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

    -- The glow effects Blizzard adds to the vault's model scene go with the scene. Its own fields
    -- (activeEffect, activeEffectInfo) stay Blizzard's: its refresh reads them.
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

-- A reward's own tooltip, as Blizzard's reward button shows it: compared with your gear while the
-- game says to (Shift held, or Always compare items).
local CompareReward = Utils.Protect("reward tooltip", function()
    if TooltipUtil and type(TooltipUtil.ShouldDoItemComparison) == "function" and TooltipUtil.ShouldDoItemComparison(GameTooltip) then
        if type(GameTooltip_ShowCompareItem) == "function" then
            GameTooltip_ShowCompareItem(GameTooltip)
        end
    elseif type(GameTooltip_HideShoppingTooltips) == "function" then
        GameTooltip_HideShoppingTooltips(GameTooltip)
    end
end)

local function ShowRewardTooltip(hit, activityFrame)
    local claim = activityFrame.bgvClaim
    if not (GameTooltip and claim) then
        return
    end
    GameTooltip:SetOwner(hit, "ANCHOR_RIGHT", -3, -6)
    if type(GameTooltip.SetWeeklyReward) == "function" then
        GameTooltip:SetWeeklyReward(claim.itemDBID)
    else
        local link = C_WeeklyRewards and type(C_WeeklyRewards.GetItemHyperlink) == "function"
            and Utils.Call(C_WeeklyRewards.GetItemHyperlink, claim.itemDBID)
        if not link then
            return
        end
        GameTooltip:SetHyperlink(link)
    end
    GameTooltip:Show()
    hit:SetScript("OnUpdate", CompareReward)
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
    hit:SetScript("OnEnter", Utils.Protect("vault slot", function()
        activityFrame.bgvHoverGen = (activityFrame.bgvHoverGen or 0) + 1
        if activityFrame.bgvClaim then
            -- a reward to choose: its tooltip; the case stays open, and clicks still select it
            ShowRewardTooltip(hit, activityFrame)
            return
        end
        BGV.Tooltip.ShowStandalone(activityFrame)
        if activityFrame.bgvSlot then
            UpdateFX(activityFrame, activityFrame.bgvSlot, true)
        end
    end))
    hit:SetScript("OnLeave", Utils.Protect("vault slot", function()
        local owner = GameTooltip and GameTooltip:GetOwner()
        if owner == hit or owner == activityFrame then
            GameTooltip:Hide()
        end
        hit:SetScript("OnUpdate", nil)
        if activityFrame.bgvClaim then
            return
        end
        local generation = activityFrame.bgvHoverGen or 0
        if not (C_Timer and type(C_Timer.After) == "function") then
            Case.Close(activityFrame)
            return
        end
        C_Timer.After(0.05, Utils.Protect("vault slot", function()
            if not activityFrame:IsShown() or (activityFrame.bgvHoverGen or 0) ~= generation then
                return
            end
            if Case.PointerOnSlot(activityFrame) then
                return
            end
            Case.Close(activityFrame)
        end))
    end))
    -- Clicks pass through to Blizzard's slot (SetPropagateMouseClicks), which selects a reward.
    hit:SetScript("OnClick", Utils.Protect("vault slot", function(_, button)
        if button ~= "LeftButton" then
            return
        end
        if IsModifiedClick() then
            -- A revealed reward links as Blizzard's reward button does: the button links it itself
            -- when it's the one under the pointer, so only clicks elsewhere on the case do here.
            local claim = activityFrame.bgvClaim
            local itemButton = activityFrame.ItemFrame
            local overButton = type(itemButton) == "table" and type(itemButton.IsMouseOver) == "function" and itemButton:IsMouseOver()
            if claim and not overButton and C_WeeklyRewards and type(C_WeeklyRewards.GetItemHyperlink) == "function"
                and type(HandleModifiedItemClick) == "function" then
                local link = Utils.Call(C_WeeklyRewards.GetItemHyperlink, claim.itemDBID)
                if link then
                    HandleModifiedItemClick(link)
                end
            end
        elseif OpenLootTableOnClick() and activityFrame.bgvSlot and activityFrame.bgvSlot.unlocked and BGV.LootTable
            and type(BGV.LootTable.ShowSlot) == "function" then
            BGV.LootTable.ShowSlot(activityFrame.bgvSlot)
        end
    end))
    activityFrame.bgvHit = hit
end

local function EnsureLines(activityFrame)
    if not activityFrame.bgvProgress then
        local progress = activityFrame:CreateFontString(nil, "OVERLAY")
        ApplyFont(progress)

        local reward = activityFrame:CreateFontString(nil, "OVERLAY")
        ApplyFont(reward)
        -- the reward line in the vault's gold
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
        if not parent or not Holds(parent) or region.bgvForcing then
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
    local alpha = ((slot and slot.unlocked) or activityFrame.bgvClaim) and 0 or 1
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

-- Opened away from the vault with rewards waiting, Blizzard dims the whole window (its Blackout,
-- which also takes the mouse) and puts its "unclaimed rewards" box on top. The game rolls those
-- rewards when the vault is opened there, for the loot spec of that moment, so the loot spec
-- button and the line saying which spec that is (AwayNote) sit above the dimming.
local function AboveDimming(weeklyRewardsFrame)
    local level = weeklyRewardsFrame:GetFrameLevel() + 20
    local blackout = weeklyRewardsFrame.Blackout
    if type(blackout) == "table" and type(blackout.GetFrameLevel) == "function" then
        level = math.max(level, blackout:GetFrameLevel() + 10)
    end
    return level
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
    button:SetFrameLevel(AboveDimming(weeklyRewardsFrame))
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

-- The line under Blizzard's "unclaimed rewards" box: which spec the rewards will be rolled for.
-- A soft dark band behind it, fading out to both sides, keeps the dimmed slots' edges out of it.
local NOTE_FADE = 48

local function AwayNote(weeklyRewardsFrame)
    local note = weeklyRewardsFrame.bgvAwayNote
    if note then
        return note
    end
    note = CreateFrame("Frame", nil, weeklyRewardsFrame)
    note.center = Utils.Pixel(note, "BACKGROUND", 0, 0, 0, 0.6)
    note.center:SetPoint("TOP")
    note.center:SetPoint("BOTTOM")
    note.left = Utils.Pixel(note, "BACKGROUND", 0, 0, 0, 0.6)
    note.left:SetPoint("TOPLEFT")
    note.left:SetPoint("BOTTOMRIGHT", note.center, "BOTTOMLEFT")
    note.right = Utils.Pixel(note, "BACKGROUND", 0, 0, 0, 0.6)
    note.right:SetPoint("TOPRIGHT")
    note.right:SetPoint("BOTTOMLEFT", note.center, "BOTTOMRIGHT")
    if type(CreateColor) == "function" then
        local clear, dark = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0.6)
        if not (pcall(note.left.SetGradient, note.left, "HORIZONTAL", clear, dark)
            and pcall(note.right.SetGradient, note.right, "HORIZONTAL", dark, clear)) then
            note.left:SetVertexColor(0, 0, 0, 0.3)
            note.right:SetVertexColor(0, 0, 0, 0.3)
        end
    end
    note.text = Utils.FontString(note, "OVERLAY", "Highlight")
    note.text:SetPoint("CENTER", 0, 0)
    note.text:SetTextColor(0.82, 0.82, 0.85)
    weeklyRewardsFrame.bgvAwayNote = note
    return note
end

local function HideAwayNote(weeklyRewardsFrame)
    local note = weeklyRewardsFrame and weeklyRewardsFrame.bgvAwayNote
    if note then
        note:Hide()
    end
end

-- Shown with Blizzard's box, and only before the rewards are rolled (ProgressWeek): once they
-- are, the loot spec no longer changes them.
local function RefreshAwayNote(weeklyRewardsFrame)
    local overlay = weeklyRewardsFrame and weeklyRewardsFrame.Overlay
    local away = ProgressWeek() and type(overlay) == "table" and type(overlay.IsShown) == "function"
        and overlay:IsShown()
    local name = away and Utils.LootSpecName(Utils.LootSpecID())
    if not name then
        HideAwayNote(weeklyRewardsFrame)
        return
    end
    local note = AwayNote(weeklyRewardsFrame)
    note:ClearAllPoints()
    note:SetPoint("TOP", overlay, "BOTTOM", 0, -6)
    note:SetFrameLevel(AboveDimming(weeklyRewardsFrame))
    note.text:SetText(string.format(L["Your rewards will be rolled for %s at the Great Vault."], "|cffffffff" .. name .. "|r"))
    local width = math.ceil(note.text:GetStringWidth() or 0)
    note.center:SetWidth(width + 16)
    note:SetSize(width + 16 + 2 * NOTE_FADE, math.ceil(note.text:GetStringHeight() or 12) + 12)
    note:Show()
    local button = weeklyRewardsFrame.bgvSpecButton
    if button then
        button:SetFrameLevel(AboveDimming(weeklyRewardsFrame))
    end
end

local function RestoreScene()
    local scene = WeeklyRewardsFrame and WeeklyRewardsFrame.ModelScene
    if scene then
        scene:SetAlpha(1)
        scene:Show()
    end
end

-- Undoes the addon's alpha 0. Whether the region shows is Blizzard's: its refresh shows or hides
-- it per slot (a checkmark only on a finished one), and the hooks above no longer interfere.
local function ReleaseRegion(region)
    if not region then
        return
    end
    region.bgvForcing = true
    region:SetAlpha(1)
    region.bgvForcing = false
end

-- Blizzard's reward button (its icon and name, and whatever a skin adds to it, such as EllesmereUI's
-- quality border a level above it) goes invisible while the case shows the reward: still there for
-- the clicks that select it, which pass through the case to it.
local function HideRewardButton(activityFrame, hidden)
    local button = activityFrame.ItemFrame
    if type(button) ~= "table" or type(button.SetAlpha) ~= "function" or (activityFrame.bgvButtonHidden or false) == hidden then
        return
    end
    activityFrame.bgvButtonHidden = hidden
    button:SetAlpha(hidden and 0 or 1)
end

local function RestoreVanilla(activityFrame)
    if not activityFrame then
        return
    end
    activityFrame.bgvSlot = nil
    activityFrame.bgvClaim = nil
    HideRewardButton(activityFrame, false)
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
    -- RewardGenerated (the sheen as rewards appear) is left alone: this runs after Blizzard's
    -- refresh, which may just have started it.
    if activityFrame.bgvBaseLevel then
        activityFrame:SetFrameLevel(activityFrame.bgvBaseLevel)
    end
    SyncSkin(activityFrame)
end

local function RestoreVault(weeklyRewardsFrame)
    if weeklyRewardsFrame then
        weeklyRewardsFrame.bgvClaimSince = nil
    end
    RestoreScene()
    HideSpecButton(weeklyRewardsFrame)
    HideAwayNote(weeklyRewardsFrame)
    local frames = weeklyRewardsFrame and weeklyRewardsFrame.Activities
    if type(frames) ~= "table" then
        return
    end
    for _, activityFrame in ipairs(frames) do
        RestoreVanilla(activityFrame)
    end
end

-- --- the rewards rolled: every slot holding one opens onto it ----------------------------------------------

-- Once the rewards are rolled, each slot holding one opens onto it, unless slot animations are off;
-- then the vault is Blizzard's. At the vault, with the rewards to choose from, the reveal plays
-- (Case.OpenClaim). Away from it, Blizzard's read-only vault dims them under its "unclaimed
-- rewards" box: they show as the reveal leaves them (Case.ShowClaims), still, and out of the
-- pointer's reach under the dimming.
local function AtVault()
    return C_WeeklyRewards ~= nil and type(C_WeeklyRewards.CanClaimRewards) == "function"
        and Utils.Call(C_WeeklyRewards.CanClaimRewards) == true
end

local function ItemIcon(itemID)
    if C_Item and type(C_Item.GetItemIconByID) == "function" then
        return Utils.Call(C_Item.GetItemIconByID, itemID)
    end
end

-- The reward a slot shows: Blizzard's own pick (its best item), known once the items have loaded.
local function ClaimReward(activityFrame)
    local info = activityFrame.info
    if type(info) ~= "table" or type(info.rewards) ~= "table" or type(activityFrame.GetDisplayedItemDBID) ~= "function" then
        return nil
    end
    local shown = Utils.Call(activityFrame.GetDisplayedItemDBID, activityFrame)
    if shown == nil then
        return nil
    end
    for _, reward in ipairs(info.rewards) do
        if type(reward) == "table" and reward.itemDBID == shown and Utils.IsUsableNumber(reward.id) then
            local icon = ItemIcon(reward.id)
            if icon then
                return { itemDBID = shown, itemID = reward.id, icon = icon }
            end
        end
    end
end

-- What a reward's reel spins through: what its slot could have awarded (Rewards.ClaimIcons), and,
-- while that's short (still loading), the vault's other rewards too, never Collect's currencies.
local CLAIM_REEL_MIN = 8

local function ClaimIcons(activityFrame, reward, held)
    local icons, pending = {}, false
    if BGV.Rewards and type(BGV.Rewards.ClaimIcons) == "function" then
        local ok, list, loading = pcall(BGV.Rewards.ClaimIcons, activityFrame.info, reward.itemID)
        if ok and type(list) == "table" then
            icons, pending = list, loading == true
        elseif not ok then
            Utils.NoteError("reward reel", list)
        end
    end
    if #icons < CLAIM_REEL_MIN then
        local seen = {}
        for _, entry in ipairs(icons) do
            seen[entry.itemID or entry.icon] = true
        end
        for _, other in ipairs(held) do
            local key = other.reward.itemID
            if not seen[key] then
                seen[key] = true
                icons[#icons + 1] = { icon = other.reward.icon, itemID = other.reward.itemID }
            end
        end
    end
    return icons, pending
end

-- A reel's own order: shuffled, at least eight items long.
local function Shuffled(list)
    local out = {}
    while #out < 8 and #list > 0 do
        for _, entry in ipairs(list) do
            out[#out + 1] = entry
        end
    end
    for i = #out, 2, -1 do
        local j = math.random(i)
        out[i], out[j] = out[j], out[i]
    end
    return out
end

-- Rewards still loading: ask again shortly, for up to CLAIM_WAIT seconds, before opening any.
local CLAIM_WAIT = 2
local claimRetry = false
local ApplyClaim

-- Reels whose lists were still loading: fuller lists swap in while they spin (up to CLAIM_REEL_WAIT
-- seconds after the reveal).
local CLAIM_REEL_WAIT = 4
local reelRetry = false

local function RefreshClaimReels(vault, held, since)
    if reelRetry or not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    reelRetry = true
    C_Timer.After(0.3, Utils.Protect("vault overlay", function()
        reelRetry = false
        if not vault:IsShown() or GetTime() - since > CLAIM_REEL_WAIT then
            return
        end
        local waiting = false
        for _, entry in ipairs(held) do
            local activityFrame = entry.frame
            if activityFrame.bgvClaim and activityFrame.bgvClaim.itemDBID == entry.reward.itemDBID and entry.reelPending then
                local icons, pending = ClaimIcons(activityFrame, entry.reward, held)
                if #icons > (entry.reelCount or 0) and Case.SetClaimIcons(activityFrame, Shuffled(icons)) then
                    entry.reelCount = #icons
                end
                entry.reelPending = pending
                waiting = waiting or pending
            end
        end
        if waiting then
            RefreshClaimReels(vault, held, since)
        end
    end))
end

local function RetryClaim(vault)
    if claimRetry or not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    claimRetry = true
    C_Timer.After(0.1, Utils.Protect("vault overlay", function()
        claimRetry = false
        if vault:IsShown() and not ProgressWeek() and not AnimationsDisabled() then
            ApplyClaim(vault)
        end
    end))
end

function ApplyClaim(vault)
    RestoreScene()
    HideSpecButton(vault)
    HideAwayNote(vault)
    vault.bgvShellReady = nil
    vault.bgvClaimSince = vault.bgvClaimSince or GetTime()
    local waited = GetTime() - vault.bgvClaimSince >= CLAIM_WAIT
    local held, loading = {}, false
    for _, activityFrame in ipairs(type(vault.Activities) == "table" and vault.Activities or {}) do
        local reward = activityFrame.ItemFrame and activityFrame.hasRewards and activityFrame:IsShown() and ClaimReward(activityFrame)
        if reward then
            held[#held + 1] = { frame = activityFrame, reward = reward }
        elseif activityFrame.ItemFrame and activityFrame.hasRewards and activityFrame:IsShown() and not waited then
            -- its item still loading: shut, so nothing shows before they all open together
            loading = true
            HideRewardButton(activityFrame, true)
            Case.Cover(activityFrame)
        else
            RestoreVanilla(activityFrame)
        end
    end
    if loading then
        for _, entry in ipairs(held) do
            HideRewardButton(entry.frame, true)
            Case.Cover(entry.frame)
        end
        RetryClaim(vault)
        return
    end
    local still = not AtVault()
    local reelsLoading, shown = false, {}
    for _, entry in ipairs(held) do
        local activityFrame = entry.frame
        -- the week's progress view goes: the slot shows its reward now
        activityFrame.bgvSlot = nil
        if activityFrame.bgvText then
            activityFrame.bgvText:Hide()
        end
        HideClosedGates(activityFrame)
        if still then
            if activityFrame.bgvHit then
                activityFrame.bgvHit:Hide()
            end
        else
            EnsureHit(activityFrame)
            activityFrame.bgvHit:Show()
        end
        HideRewardButton(activityFrame, true)
        local fresh = not (activityFrame.bgvClaim and activityFrame.bgvClaim.itemDBID == entry.reward.itemDBID)
        activityFrame.bgvClaim = entry.reward
        if fresh then
            local icons, pending = ClaimIcons(activityFrame, entry.reward, held)
            if still then
                shown[#shown + 1] = { frame = activityFrame, reward = entry.reward, icons = Shuffled(icons) }
            else
                entry.reelCount, entry.reelPending = #icons, pending
                reelsLoading = reelsLoading or pending
                Case.OpenClaim(activityFrame, entry.reward, Shuffled(icons))
            end
        end
        -- Blizzard's own art and text under the case go, as on the progress week's slots
        HideDefaultCaption(activityFrame)
        HideDefaultShine(activityFrame)
        SyncSkin(activityFrame)
    end
    if #shown > 0 then
        Case.ShowClaims(shown)
    end
    if reelsLoading then
        RefreshClaimReels(vault, held, GetTime())
    end
end

-- Out of the progress week: the rewards opened onto (at the vault or away from it), or Blizzard's
-- vault with slot animations off. Nothing is opened on a hidden vault.
local function LeaveWeek(weeklyRewardsFrame)
    if weeklyRewardsFrame and weeklyRewardsFrame:IsShown() and not AnimationsDisabled() then
        ApplyClaim(weeklyRewardsFrame)
    else
        RestoreVault(weeklyRewardsFrame)
    end
end

-- A slot the addon doesn't show (not in the vault's snapshot): all Blizzard's again, its tooltip too.
function UI.Clear(activityFrame)
    RestoreVanilla(activityFrame)
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
        LeaveWeek(weeklyRewardsFrame)
        return
    end

    weeklyRewardsFrame.bgvShellReady = true
    RefreshSpecButton(weeklyRewardsFrame)
    RefreshAwayNote(weeklyRewardsFrame)
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
    C_Timer.After(0, Utils.Protect("reel preload", function()
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
        local Step
        -- A step that fails ends this run (the error noted), so the next show starts it again.
        local function SafeStep()
            local ok, err = pcall(Step)
            if not ok then
                weeklyRewardsFrame.bgvPumping = nil
                Utils.NoteError("reel preload", err)
            end
        end
        function Step()
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
                    C_Timer.After(PUMP_STALL_DELAY, SafeStep)
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
                C_Timer.After(0.05, SafeStep)
            else
                weeklyRewardsFrame.bgvPumping = nil
                weeklyRewardsFrame.bgvPumpIndex = nil
            end
        end
        C_Timer.After(0.05, SafeStep)
    end))
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
        LeaveWeek(weeklyRewardsFrame)
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
    if UI.hooked or type(WeeklyRewardsFrame) ~= "table" or type(hooksecurefunc) ~= "function" then
        return false
    end

    -- The hooks go on the vault frame itself: it copied its methods from WeeklyRewardsMixin when it
    -- was made, so hooks on the mixin never reach it (in game, WeeklyRewardsFrame.Refresh ~=
    -- WeeklyRewardsMixin.Refresh once hooked). Blizzard refreshes on every show (FullRefresh) and
    -- on every WEEKLY_REWARDS_UPDATE while it's open. The slots' own art and text are kept down
    -- by the hooks on those regions (BuryShownRegion, BuryDefaultRegion, KillAnim).
    if type(WeeklyRewardsFrame.Refresh) == "function" then
        Hook(WeeklyRewardsFrame, "Refresh", function(self)
            -- the skin makes its card a frame after the vault shows, in either week
            if self:IsShown() then
                SyncSkinSoon(self)
            end
            if not ProgressWeek() then
                LeaveWeek(self)
                return
            end
            if not self:IsShown() then
                return
            end
            if self.bgvShellReady then
                KeepShell(self)
                -- reel lists still loading when it last closed carry on
                UI.ScheduleContent(self)
                return
            end
            UI.SafeUpdate(self)
            UI.ScheduleContent(self)
        end)
    end

    if WeeklyRewardsFrame and not WeeklyRewardsFrame.bgvHideHook then
        WeeklyRewardsFrame.bgvHideHook = true
        HookScript(WeeklyRewardsFrame, "OnHide", function(self)
            CloseOpenGates(self)
        end)
    end

    -- Every refresh decides on Blizzard's "unclaimed rewards" box here, so the line under it follows.
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.UpdateOverlay) == "function" and not WeeklyRewardsFrame.bgvOverlayHook then
        WeeklyRewardsFrame.bgvOverlayHook = true
        Hook(WeeklyRewardsFrame, "UpdateOverlay", function(self)
            RefreshAwayNote(self)
        end)
    end

    -- Pointing at Collect saddens the gates (Faces.lua).
    if BGV.Faces and WeeklyRewardsFrame then
        BGV.Faces.Hook(WeeklyRewardsFrame)
    end

    UI.hooked = true
    return true
end

function UI.RefreshOpenFrame()
    local vault = WeeklyRewardsFrame
    if not (vault and type(vault.IsShown) == "function" and vault:IsShown()) then
        -- changed while the vault was closed: it's laid out afresh when it shows (the refresh hook)
        if vault then
            vault.bgvShellReady = nil
        end
        return
    end
    if not ProgressWeek() then
        LeaveWeek(vault)
        return
    end
    UI.SafeUpdate(vault)
end
