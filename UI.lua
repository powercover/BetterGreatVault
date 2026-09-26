local _, BGV = ...

BGV.UI = {}

local UI = BGV.UI
local Utils = BGV.Utils

local function AnimationsDisabled()
    return BetterGreatVaultDB and BetterGreatVaultDB.disableAnimations == true
end

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
local GATE_CORNER = 16
local REEL_LEFT = 2
local REEL_RIGHT = 4

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

    local window = CreateFrame("Frame", nil, fx)
    window:SetPoint("TOPLEFT", fx, "TOPLEFT", REEL_LEFT, -GATE_CORNER)
    window:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", -REEL_RIGHT, GATE_CORNER)
    window:EnableMouse(false)
    if window.SetClipsChildren then
        window:SetClipsChildren(true)
    end
    fx.window = window

    local shade = window:CreateTexture(nil, "BACKGROUND")
    shade:SetAllPoints()
    ColorTexture(shade, 0.02, 0.015, 0.01, 1)

    local reel = CreateFrame("Frame", nil, window)
    reel:SetWidth(CASE_STRIDE * CASE_SLOTS)
    reel:SetPoint("TOPLEFT", window, "TOPLEFT", 0, 0)
    reel:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", 0, 0)
    fx.reel = reel
    fx.cells = {}
    for index = 1, CASE_SLOTS do
        local holder = CreateFrame("Frame", nil, reel)
        holder:SetWidth(CASE_STRIDE)
        holder:SetPoint("TOPLEFT", reel, "TOPLEFT", (index - 1) * CASE_STRIDE, 0)
        holder:SetPoint("BOTTOMLEFT", reel, "BOTTOMLEFT", (index - 1) * CASE_STRIDE, 0)
        local back = holder:CreateTexture(nil, "BORDER")
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
        ColorTexture(backing, 0.104, 0.083, 0.075, 1)
        gate.backing = backing

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

    local marker = CreateFrame("Frame", nil, activityFrame)
    marker:SetFrameLevel(activityFrame:GetFrameLevel() + 5)
    marker:SetPoint("TOP", fx, "TOP", 0, -GATE_CORNER)
    marker:SetPoint("BOTTOM", fx, "BOTTOM", 0, GATE_CORNER)
    marker:SetWidth(2)
    marker:EnableMouse(false)
    local markerLine = marker:CreateTexture(nil, "OVERLAY")
    markerLine:SetAllPoints()
    marker.line = markerLine
    marker:Hide()
    fx.marker = marker
    fx.markerLine = markerLine

    local function MakeSeam()
        local seam = CreateFrame("Frame", nil, activityFrame)
        seam:SetFrameLevel(activityFrame:GetFrameLevel() + 9)
        seam:SetHeight(2)
        seam:EnableMouse(false)
        local seamLine = seam:CreateTexture(nil, "OVERLAY")
        seamLine:SetAllPoints()
        seam.line = seamLine
        seam:Hide()
        return seam
    end

    fx.topSeam = MakeSeam()
    fx.bottomSeam = MakeSeam()

    fx.offset = 0
    fx.cursor = 1
    fx.reveal = 0
    fx.owner = activityFrame
    fx:Hide()
    activityFrame.bgvFX = fx
end

local SPEC_LINE = {
    [250] = { 0.78, 0.06, 0.10 },
    [251] = { 0.55, 0.86, 1.00 },
    [252] = { 0.35, 0.82, 0.28 },
    [577] = { 0.20, 0.85, 0.45 },
    [581] = { 0.55, 0.20, 0.75 },
    [1480] = { 0.48, 0.22, 0.90 },
    [102] = { 0.35, 0.55, 1.00 },
    [103] = { 1.00, 0.48, 0.12 },
    [104] = { 0.82, 0.52, 0.16 },
    [105] = { 0.25, 0.82, 0.38 },
    [1467] = { 0.90, 0.28, 0.20 },
    [1468] = { 0.22, 0.75, 0.55 },
    [1473] = { 0.82, 0.62, 0.28 },
    [253] = { 0.78, 0.68, 0.28 },
    [254] = { 0.55, 0.75, 0.92 },
    [255] = { 0.90, 0.42, 0.16 },
    [62] = { 0.62, 0.38, 0.95 },
    [63] = { 1.00, 0.42, 0.12 },
    [64] = { 0.62, 0.90, 1.00 },
    [268] = { 0.78, 0.48, 0.16 },
    [269] = { 0.25, 0.88, 0.68 },
    [270] = { 0.45, 0.85, 0.70 },
    [65] = { 1.00, 0.86, 0.42 },
    [66] = { 0.72, 0.74, 0.86 },
    [70] = { 1.00, 0.72, 0.22 },
    [256] = { 0.82, 0.88, 1.00 },
    [257] = { 1.00, 0.94, 0.70 },
    [258] = { 0.55, 0.28, 0.85 },
    [259] = { 0.32, 0.78, 0.22 },
    [260] = { 0.85, 0.22, 0.16 },
    [261] = { 0.55, 0.40, 0.75 },
    [262] = { 0.28, 0.55, 1.00 },
    [263] = { 0.88, 0.50, 0.16 },
    [264] = { 0.22, 0.62, 0.90 },
    [265] = { 0.58, 0.32, 0.85 },
    [266] = { 0.38, 0.75, 0.28 },
    [267] = { 0.95, 0.32, 0.12 },
    [71] = { 0.72, 0.28, 0.16 },
    [72] = { 0.90, 0.16, 0.14 },
    [73] = { 0.70, 0.58, 0.42 },
}

local function AccentColor()
    if not BetterGreatVaultDB or BetterGreatVaultDB.useSpecAccent ~= false then
        local specID = Utils.CurrentSpecID()
        return specID and SPEC_LINE[specID] or { 0.85, 0.65, 0.2 }
    end
    local saved = BetterGreatVaultDB.accentColor
    if type(saved) == "table" then
        local r = saved.r or saved[1]
        local g = saved.g or saved[2]
        local b = saved.b or saved[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { r, g, b }
        end
    end
    return { 0.85, 0.65, 0.2 }
end

local function ColorMarker(fx)
    local line = fx and fx.markerLine
    if not line then
        return
    end
    local color = AccentColor()
    ColorTexture(line, color[1], color[2], color[3], 0.95)
    for _, seam in ipairs({ fx.topSeam, fx.bottomSeam }) do
        if seam and seam.line then
            ColorTexture(seam.line, 0.62, 0.48, 0.28, 1)
        end
    end
end

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
        if activityFrame.bgvFX then
            ColorMarker(activityFrame.bgvFX)
        end
    end
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
    if height and height >= 4 then
        fx.slotHeight = height
    else
        height = fx.slotHeight or 64
    end
    local half = height * 0.5
    local travel = math.max(0, half - GATE_CORNER)
    local covered = GATE_CORNER + travel * (1 - (fx.reveal or 0))
    if covered > half then
        covered = half
    end
    fx:SetAlpha(1)
    local level = fx:GetFrameLevel()
    if fx.window then
        fx.window:SetFrameLevel(level + 1)
    end
    if fx.reel then
        fx.reel:SetFrameLevel(level + 1)
        for _, cell in ipairs(fx.cells or {}) do
            cell:SetFrameLevel(level + 1)
        end
    end
    if fx.marker then
        fx.marker:SetFrameLevel(level + 2)
    end
    if fx.topDoor then
        fx.topDoor:SetFrameLevel(level + 8)
        fx.bottomDoor:SetFrameLevel(level + 8)
    end
    for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
        gate:SetHeight(covered)
        gate:Show()
    end
    if fx.topSeam then
        fx.topSeam:SetFrameLevel(level + 9)
        fx.topSeam:ClearAllPoints()
        fx.topSeam:SetPoint("LEFT", fx, "TOPLEFT", REEL_LEFT, -covered)
        fx.topSeam:SetPoint("RIGHT", fx, "TOPRIGHT", -REEL_RIGHT, -covered)
    end
    if fx.bottomSeam then
        fx.bottomSeam:SetFrameLevel(level + 9)
        fx.bottomSeam:ClearAllPoints()
        fx.bottomSeam:SetPoint("LEFT", fx, "BOTTOMLEFT", REEL_LEFT, covered)
        fx.bottomSeam:SetPoint("RIGHT", fx, "BOTTOMRIGHT", -REEL_RIGHT, covered)
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

local PaintReel, PlaceReel, RestClosed, ShutGates, VaultIsOpen, CloseCase

local function PointerOnSlot(activityFrame)
    local hit = activityFrame and activityFrame.bgvHit
    if not hit then
        return false
    end
    local function Owned(frame)
        if frame == GameTooltip then
            local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
            return owner == hit or owner == activityFrame
        end
        while frame do
            if frame == hit or frame == activityFrame then
                return true
            end
            if not frame.GetParent then
                return false
            end
            frame = frame:GetParent()
        end
        return false
    end
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        local top = type(foci) == "table" and foci[1] or nil
        if top then
            return Owned(top)
        end
    elseif type(GetMouseFocus) == "function" then
        local focus = GetMouseFocus()
        if focus then
            return Owned(focus)
        end
    end
    return hit:IsMouseOver()
end

local function EnsureReel(fx)
    if fx.ticker or not (C_Timer and type(C_Timer.NewTicker) == "function") then
        return
    end
    fx.ticker = C_Timer.NewTicker(0.02, function()
        if not VaultIsOpen() then
            if fx.owner then
                ShutGates(fx.owner)
            end
            return
        end
        if (fx.revealTarget or 0) > 0 and fx.owner and not PointerOnSlot(fx.owner) then
            CloseCase(fx.owner)
        end
        if (fx.revealTarget or 0) ~= fx.revealAim then
            fx.revealAim = fx.revealTarget or 0
            fx.revealFrom = fx.reveal or 0
            fx.revealClock = 0
        end
        fx.revealClock = (fx.revealClock or 0) + 0.02
        local delta = (fx.revealAim or 0) - (fx.revealFrom or 0)
        local duration = math.max(0.16, 0.5 * math.abs(delta))
        local progress = math.min(1, fx.revealClock / duration)
        local eased = progress * progress * (3 - 2 * progress)
        fx.reveal = (fx.revealFrom or 0) + delta * eased
        if progress >= 1 then
            fx.reveal = fx.revealAim or 0
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
            fx:Hide()
            if fx.marker then
                fx.marker:Hide()
            end
            if fx.topSeam then
                fx.topSeam:Hide()
                fx.bottomSeam:Hide()
            end
            LayoutDoors(fx)
            FadeCaption(fx.owner, 1)
        end
    end)
end

function PlaceReel(fx)
    local window = fx.window or fx
    fx.reel:SetWidth(CASE_STRIDE * CASE_SLOTS)
    fx.reel:ClearAllPoints()
    fx.reel:SetPoint("TOPLEFT", window, "TOPLEFT", fx.offset or 0, 0)
    fx.reel:SetPoint("BOTTOMLEFT", window, "BOTTOMLEFT", fx.offset or 0, 0)
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
        hooksecurefunc(region, "Show", Force)
        hooksecurefunc(region, "SetAlpha", function(self, alpha)
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
        anim:HookScript("OnPlay", function(self)
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
            ColorTexture(cell.back, color[1], color[2], color[3], 1)
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
    StopReel(fx)
    fx.reveal = 0
    fx.revealTarget = 0
    fx:Hide()
    if fx.marker then
        fx.marker:Hide()
    end
    if fx.topSeam then
        fx.topSeam:Hide()
        fx.bottomSeam:Hide()
    end
    if fx.topDoor then
        fx.topDoor:Hide()
    end
    if fx.bottomDoor then
        fx.bottomDoor:Hide()
    end
    FadeCaption(activityFrame, 1)
end

local cachedVaultBackground

local function VaultBackground()
    if cachedVaultBackground then
        return cachedVaultBackground
    end
    local vault = WeeklyRewardsFrame
    if not vault then
        return nil
    end
    if vault.Background then
        cachedVaultBackground = vault.Background
        return vault.Background
    end
    if type(vault.GetRegions) ~= "function" then
        return nil
    end
    for _, region in ipairs({ vault:GetRegions() }) do
        if region and region.GetObjectType and region:GetObjectType() == "Texture" and region.GetAtlas then
            local atlas = region:GetAtlas()
            if type(atlas) == "string" and atlas:find("weeklyrewards", 1, true) and not atlas:find("reward", 1, true) then
                cachedVaultBackground = region
                return region
            end
        end
    end
end

local function PaintGateBacking(gate)
    local backing = gate and gate.backing
    if not backing then
        return
    end
    backing:ClearAllPoints()
    backing:SetAllPoints(gate)
    ColorTexture(backing, 0.104, 0.083, 0.075, 1)
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
        PaintGateBacking(gate)
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
    if fx.window then
        fx.window:SetFrameLevel(level + 1)
    end
    if fx.reel then
        fx.reel:SetFrameLevel(level + 1)
    end
    if fx.marker then
        fx.marker:SetFrameLevel(level + 2)
    end
    if fx.topDoor then
        fx.topDoor:SetFrameLevel(level + 8)
        fx.bottomDoor:SetFrameLevel(level + 8)
    end
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(level + 8)
    end
    if activityFrame.bgvHit then
        activityFrame.bgvHit:SetFrameLevel(level + 10)
    end
end

local function StartCase(activityFrame)
    if AnimationsDisabled() then
        return
    end
    if not activityFrame or not activityFrame.IsShown or not activityFrame:IsShown() then
        return
    end
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    local icons = fx.icons

    PlaceCase(activityFrame)
    fx.revealTarget = 1
    if type(icons) == "table" and #icons > 0 and not fx.reelReady then
        fx.cursor = math.random(#icons)
        fx.offset = 0
        PaintReel(fx)
        PlaceReel(fx)
        fx.reelReady = true
    end
    fx:Show()
    if fx.marker then
        ColorMarker(fx)
        fx.marker:Show()
    end
    if fx.topSeam then
        fx.topSeam:Show()
        fx.bottomSeam:Show()
    end
    LayoutDoors(fx)
    EnsureReel(fx)
    FadeCaption(activityFrame, 0)
end

function CloseCase(activityFrame)
    if AnimationsDisabled() then
        return
    end
    local fx = activityFrame and activityFrame.bgvFX
    if not fx or not fx:IsShown() then
        return
    end
    fx.revealTarget = 0
    EnsureReel(fx)
end

function VaultIsOpen()
    return WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown()
end

function ShutGates(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    StopReel(fx)
    local wasOpen = (fx.reveal or 0) > 0
    fx.reveal = 0
    fx.revealTarget = 0
    fx.revealAim = 0
    if fx.marker then
        fx.marker:Hide()
    end
    if fx.topSeam then
        fx.topSeam:Hide()
        fx.bottomSeam:Hide()
    end
    if wasOpen and activityFrame.bgvSlot and activityFrame.bgvSlot.unlocked and fx.topDoor then
        local height = fx.slotHeight
        if not height or height < 4 then
            height = fx:GetHeight()
        end
        if height and height >= 4 then
            local half = height * 0.5
            fx.topDoor:SetHeight(half)
            fx.bottomDoor:SetHeight(half)
            fx.topDoor:Show()
            fx.bottomDoor:Show()
        end
    end
    fx:Hide()
    local text = activityFrame.bgvText
    if text then
        if text.bgvFade then
            text.bgvFade:Stop()
        end
        text.bgvFadeTarget = 1
        text:SetAlpha(1)
    end
end

local function RaiseAboveGlow(activityFrame)
    local scene = WeeklyRewardsFrame and WeeklyRewardsFrame.ModelScene
    local sceneLevel = scene and scene.GetFrameLevel and scene:GetFrameLevel() or 300
    local parent = activityFrame:GetParent()
    if scene and parent and scene.GetParent and scene:GetParent() == parent then
        if not activityFrame.bgvBaseLevel then
            activityFrame.bgvBaseLevel = activityFrame:GetFrameLevel()
        end
        if activityFrame:GetFrameLevel() <= sceneLevel then
            activityFrame:SetFrameLevel(sceneLevel + 20)
        end
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
        local backing = door:CreateTexture(nil, "BACKGROUND")
        backing:SetAllPoints(door)
        ColorTexture(backing, 0.104, 0.083, 0.075, 1)
        door.backing = backing

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
    if activityFrame.bgvFX then
        StopFX(activityFrame)
    end
    RaiseAboveGlow(activityFrame)
    EnsureClosedGates(activityFrame)
    local closed = activityFrame.bgvClosed
    local slot = activityFrame:GetHeight()
    if not slot or slot < 4 then
        slot = 126
    end
    local half = slot * 0.5
    local atlas = "evergreen-weeklyrewards-reward-unlocked"
    local bg = activityFrame.Background
    if bg and type(bg.GetAtlas) == "function" then
        local current = bg:GetAtlas()
        if type(current) == "string" and current ~= "" then
            atlas = current
        end
    end
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
        PaintGateBacking(door)
        door:Show()
    end
    closed:SetFrameLevel(level)
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(level + 2)
        activityFrame.bgvText:SetAlpha(1)
    end
    closed:Show()
end

function RestClosed(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    StopReel(fx)
    fx.reveal = 0
    fx.revealTarget = 0
    fx.revealAim = 0
    if fx.marker then
        fx.marker:Hide()
    end
    if fx.topSeam then
        fx.topSeam:Hide()
        fx.bottomSeam:Hide()
    end
    PlaceCase(activityFrame)
    LayoutDoors(fx)
    RaiseAboveGlow(activityFrame)
    if fx.topDoor then
        fx.topDoor:SetFrameLevel(activityFrame:GetFrameLevel() + 8)
        fx.bottomDoor:SetFrameLevel(activityFrame:GetFrameLevel() + 8)
    end
    fx:Hide()
    FadeCaption(activityFrame, 1)
end

local function UpdateFX(activityFrame, slot, fromEnter)
    if AnimationsDisabled() then
        if slot and slot.unlocked then
            ShowClosedGates(activityFrame)
        else
            HideClosedGates(activityFrame)
            if activityFrame.bgvFX then
                StopFX(activityFrame)
            end
        end
        return
    end
    HideClosedGates(activityFrame)
    EnsureFX(activityFrame)
    local fx = activityFrame.bgvFX
    local hovering = fromEnter or (activityFrame.bgvHit and activityFrame.bgvHit:IsMouseOver())
    if hovering and slot and slot.unlocked and VaultIsOpen() then
        local icons = BGV.Rewards.PossibleIcons(slot)
        if fx.iconKey ~= icons then
            fx.reelReady = nil
        end
        fx.icons = icons
        fx.iconKey = icons
        StartCase(activityFrame)
        return
    end
    if slot and slot.unlocked then
        if not fx.ticker and (fx.reveal or 0) <= 0 then
            RestClosed(activityFrame)
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
            if PointerOnSlot(activityFrame) then
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
        if button == "LeftButton" and not IsModifiedClick() and activityFrame.bgvSlot and BGV.LootTable and type(BGV.LootTable.ShowSlot) == "function" then
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
        region:HookScript("OnShow", Force)
    elseif type(hooksecurefunc) == "function" then
        hooksecurefunc(region, "Show", Force)
    end
    if type(hooksecurefunc) == "function" then
        hooksecurefunc(region, "SetAlpha", function(_, alpha)
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

local function ProgressWeek()
    return not (BGV.Rewards and BGV.Rewards.ShowingWeeklyProgress) or BGV.Rewards.ShowingWeeklyProgress()
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
    StopFX(activityFrame)
    HideClosedGates(activityFrame)
    PlaceLock(activityFrame, nil)
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
end

local function RestoreVault(weeklyRewardsFrame)
    RestoreScene()
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
    StopFX(activityFrame)
    HideClosedGates(activityFrame)
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
    RaiseAboveGlow(activityFrame)
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
        BGV.lastError = err
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
        BGV.lastError = err
    end
end

function UI.ScheduleContent(weeklyRewardsFrame)
    if not ProgressWeek() then
        return
    end
    if not weeklyRewardsFrame or not VaultIsOpen() or weeklyRewardsFrame.bgvContentQueued then
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
        if not VaultIsOpen() then
            return
        end
        local ok, snapshot = pcall(BGV.GreatVault.GetSnapshot)
        if not ok or type(snapshot) ~= "table" then
            return
        end
        for _, slot in ipairs(snapshot) do
            if slot.unlocked and not AnimationsDisabled() then
                BGV.Rewards.PossibleIcons(slot)
            end
        end
    end)
end

local function CloseOpenGates(weeklyRewardsFrame)
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
        ShutGates(activityFrame)
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
        hooksecurefunc(WeeklyRewardsMixin, "Refresh", function(self)
            if not ProgressWeek() then
                RestoreVault(self)
                return
            end
            if shellApplying or not self:IsShown() then
                return
            end
            if self.bgvShellReady then
                KeepShell(self)
                return
            end
            UI.SafeUpdate(self)
            UI.ScheduleContent(self)
        end)
    end

    if type(WeeklyRewardsMixin.OnShow) == "function" then
        hooksecurefunc(WeeklyRewardsMixin, "OnShow", function(self)
            if not ProgressWeek() then
                RestoreVault(self)
                return
            end
            if self.bgvShellReady then
                KeepShell(self)
                return
            end
            UI.SafeUpdate(self)
            UI.ScheduleContent(self)
        end)
    end

    if type(WeeklyRewardsMixin.OnHide) == "function" then
        hooksecurefunc(WeeklyRewardsMixin, "OnHide", function(self)
            CloseOpenGates(self)
        end)
    end

    if WeeklyRewardsFrame and not WeeklyRewardsFrame.bgvHideHook then
        WeeklyRewardsFrame.bgvHideHook = true
        WeeklyRewardsFrame:HookScript("OnHide", function(self)
            CloseOpenGates(self)
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetActiveEffect) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "SetActiveEffect", function(self)
            if self.bgvSlot then
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.Refresh) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "Refresh", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
                HideDefaultShine(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.SetProgressText) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "SetProgressText", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
            end
        end)
    end

    if type(WeeklyRewardsActivityMixin) == "table" and type(WeeklyRewardsActivityMixin.OnShow) == "function" then
        hooksecurefunc(WeeklyRewardsActivityMixin, "OnShow", function(self)
            if self.bgvSlot then
                HideDefaultCaption(self)
                HideDefaultShine(self)
            end
        end)
    end

    if WeeklyRewardsFrame and WeeklyRewardsFrame.HookScript and not WeeklyRewardsFrame.bgvAccentShow then
        WeeklyRewardsFrame.bgvAccentShow = true
        WeeklyRewardsFrame:HookScript("OnShow", function()
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
