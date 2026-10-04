local _, BGV = ...

-- The case: what a completed Great Vault slot shows while you point at it. Its face opens onto a
-- reel of the loot the slot can give, in one of several opening styles: the one matching your
-- specialization, one picked in the settings, or a random one. A slot runs one ticker while it
-- opens, stays open or closes, and nothing once it's closed; a style makes its textures the first
-- time the slot uses it, and its effects come from a small pool of textures that is reused.
BGV.Case = {}

local Case = BGV.Case
local Utils = BGV.Utils
local L = BGV.L

local MEDIA = "Interface\\AddOns\\BetterGreatVault\\Media\\"
local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DEFAULT_ATLAS = "evergreen-weeklyrewards-reward-unlocked"

local CASE_ICON = 40
local CASE_STRIDE = 56
local CASE_SLOTS = 12
local GATE_CORNER = 16
local REEL_LEFT = 2
local REEL_RIGHT = 4
local REEL_TICK = 1 / 60
local REEL_REFRESH = 0.25
local REEL_REFRESH_EMPTY = 0.1
local SLOT_W, SLOT_H = 219, 126 -- Blizzard's slot, until the frame reports its own size
local PARTICLES = 32

-- The vault's rewards to choose from (Case.OpenClaim): the reel spins at CLAIM_SPIN until the case
-- is open, then slows to a stop with the reward at the marker, CLAIM_PASS more items going by. The
-- reward then grows by CLAIM_ZOOM over CLAIM_GROW seconds, centred in the space above the caption
-- bar (CLAIM_BAR high, along the reel's bottom) that holds its name and item level.
local CLAIM_SPIN = 380
local CLAIM_PASS = 3
local CLAIM_BAR = 30
local CLAIM_ZOOM, CLAIM_LIFT, CLAIM_GROW = 0.3, CLAIM_BAR / 2, 0.4
-- Once it has landed, grown and shown its name, with nothing left in the air, a reward's case stays
-- as it is without a frame's work (every slot may be open at once while a reward is chosen).
local CLAIM_SETTLE, CLAIM_NAME_WAIT = 1, 5

-- Best-in-Slot tiers behind the reel's items (Bis.lua).
local TIER_BACK = {
    D = { 0.45, 0.45, 0.45 },
    C = { 0.12, 0.55, 0.18 },
    B = { 0.15, 0.35, 0.85 },
    A = { 0.55, 0.22, 0.78 },
    S = { 0.85, 0.62, 0.08 },
}

-- Frost Shatter's ice plate in pieces (Media\CaseFrostShards.tga, from make_case_media.py): each
-- piece's place in the texture, its size and centre in the slot (UI units, up is +y), and where
-- it sits from the crack's centre (it flies that way).
local FROST_SHARDS = {
    { l = 0.00195, r = 0.09180, t = 0.00391, b = 0.22656, w = 46, h = 57, x = -1.5, y = 0.5, dx = -0.5, dy = 1.0 },
    { l = 0.09570, r = 0.28711, t = 0.00391, b = 0.20703, w = 98, h = 52, x = 57.5, y = -37.0, dx = 43.2, dy = -38.0 },
    { l = 0.29102, r = 0.38672, t = 0.00391, b = 0.18359, w = 49, h = 46, x = 12.0, y = -40.0, dx = 7.7, dy = -42.1 },
    { l = 0.39062, r = 0.53906, t = 0.00391, b = 0.18750, w = 76, h = 47, x = -43.5, y = -39.5, dx = -29.2, dy = -42.0 },
    { l = 0.54297, r = 0.72070, t = 0.00391, b = 0.23828, w = 91, h = 60, x = -64.0, y = -33.0, dx = -67.2, dy = -31.5 },
    { l = 0.72461, r = 0.90234, t = 0.00391, b = 0.31250, w = 91, h = 79, x = -64.0, y = 23.5, dx = -66.6, dy = 26.0 },
    { l = 0.00195, r = 0.14258, t = 0.32031, b = 0.49609, w = 72, h = 45, x = -40.5, y = 40.5, dx = -27.3, dy = 44.0 },
    { l = 0.14648, r = 0.25781, t = 0.32031, b = 0.49219, w = 57, h = 44, x = 19.0, y = 41.0, dx = 13.1, dy = 44.4 },
    { l = 0.26172, r = 0.44727, t = 0.32031, b = 0.52344, w = 95, h = 52, x = 62.0, y = 37.0, dx = 61.4, dy = 44.8 },
    { l = 0.45117, r = 0.63086, t = 0.32031, b = 0.81250, w = 92, h = 126, x = 63.5, y = 0.0, dx = 73.8, dy = -11.9 },
}

-- The styles: each specialization's own (`class` and `spec`, its specialization ID), and the
-- extras that belong to none. CaseStyles.lua adds most of them (Case.AddStyle).
Case.STYLES = {
    { id = "vault", name = "Vault Door" },
    { id = "classic", name = "Classic" },
    { id = "cartoon", name = "Old Cartoon" },
    { id = "bandit", name = "One-Armed Bandit", class = "ROGUE", spec = 260 },
    { id = "arcane", name = "Arcane Portal", class = "MAGE", spec = 62 },
    { id = "frost", name = "Frost Shatter", class = "MAGE", spec = 64 },
    { id = "fel", name = "Fel Fire", class = "DEMONHUNTER", spec = 577 },
}
Case.SPEC = "spec"
Case.RANDOM = "random"

-- "Match specialization": the specialization's style; one without a style opens as Vault Door.
local SPEC_STYLE = {} -- specialization ID -> style id
-- Random picks from every style but Classic.
local RANDOM_POOL = {}
local STYLE = {} -- id -> the style, below

-- --- helpers ----------------------------------------------------------------------------------------

local function Clamp01(x)
    if x < 0 then
        return 0
    elseif x > 1 then
        return 1
    end
    return x
end

local function Smooth(x)
    x = Clamp01(x)
    return x * x * (3 - 2 * x)
end

local function EaseOutCubic(x)
    x = Clamp01(x) - 1
    return x * x * x + 1
end

local function EaseInCubic(x)
    x = Clamp01(x)
    return x * x * x
end

local function EaseInOut(x)
    x = Clamp01(x)
    if x < 0.5 then
        return 4 * x * x * x
    end
    local y = -2 * x + 2
    return 1 - y * y * y / 2
end

-- Overshoots the end a little and settles back: `s` sets how far.
local function EaseOutBack(x, s)
    x = Clamp01(x) - 1
    return 1 + x * x * ((s + 1) * x + s)
end

local function EaseOutBounce(x)
    x = Clamp01(x)
    local n, d = 7.5625, 2.75
    if x < 1 / d then
        return n * x * x
    elseif x < 2 / d then
        x = x - 1.5 / d
        return n * x * x + 0.75
    elseif x < 2.5 / d then
        x = x - 2.25 / d
        return n * x * x + 0.9375
    end
    x = x - 2.625 / d
    return n * x * x + 0.984375
end

local function Random(low, high)
    return low + math.random() * (high - low)
end

-- The animations' clock: the game's, run ahead by what was played in one go (Case.ShowClaims), so a
-- case played to its end at once sees the times it would have seen playing.
local clockAhead = 0

local function Now()
    return GetTime() + clockAhead
end

local atan2 = math.atan2 or math.atan

local AnimationsDisabled = Utils.AnimationsOff

local function ColorTexture(texture, r, g, b, a)
    if texture.SetColorTexture then
        texture:SetColorTexture(r, g, b, a or 1)
    else
        texture:SetTexture(WHITE)
        texture:SetVertexColor(r, g, b, a or 1)
    end
end

-- --- the style setting -------------------------------------------------------------------------------

function Case.Choice()
    local value = BetterGreatVaultDB and BetterGreatVaultDB.vaultStyle
    if value == Case.SPEC or value == Case.RANDOM or STYLE[value] then
        return value
    end
    return Case.SPEC
end

-- The style the current specialization opens with.
function Case.SpecStyle()
    local specID = Utils.CurrentSpecID()
    return specID and SPEC_STYLE[specID] or "vault"
end

function Case.StyleName(id)
    for _, style in ipairs(Case.STYLES) do
        if style.id == id then
            return L[style.name]
        end
    end
    if id == Case.RANDOM then
        return L["Random"]
    end
    return L["Match specialization"]
end

-- The style for this opening, and its id: Random never repeats the slot's last one.
local function PickStyle(fx)
    -- The settings' preview plays the choice it was given (Case.ShowPreview).
    local choice = fx.previewChoice or Case.Choice()
    local id
    if choice == Case.RANDOM then
        for _ = 1, 8 do
            id = RANDOM_POOL[math.random(#RANDOM_POOL)]
            if id ~= fx.lastStyle then
                break
            end
        end
        fx.lastStyle = id
    elseif choice == Case.SPEC then
        id = Case.SpecStyle()
    else
        id = choice
    end
    if not STYLE[id] then
        id = "vault"
    end
    return STYLE[id], id
end

-- --- the vault, the pointer, the caption ----------------------------------------------------------------

local function VaultIsOpen()
    return WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown()
end
Case.VaultIsOpen = VaultIsOpen

-- No upvalues over hit/activityFrame so this can be a module-level function instead of a
-- closure re-allocated on every PointerOnSlot call (which runs every reel tick, up to 60/sec).
local function FrameOwnsTarget(target, hit, activityFrame)
    if target == GameTooltip then
        local owner = GameTooltip.GetOwner and GameTooltip:GetOwner()
        return owner == hit or owner == activityFrame
    end
    while target do
        if target == hit or target == activityFrame then
            return true
        end
        if not target.GetParent then
            return false
        end
        target = target:GetParent()
    end
    return false
end

local function PointerOnSlot(activityFrame)
    local hit = activityFrame and activityFrame.bgvHit
    if not hit then
        return false
    end
    if type(GetMouseFoci) == "function" then
        local foci = GetMouseFoci()
        local top = type(foci) == "table" and foci[1] or nil
        if top then
            return FrameOwnsTarget(top, hit, activityFrame)
        end
    elseif type(GetMouseFocus) == "function" then
        local focus = GetMouseFocus()
        if focus then
            return FrameOwnsTarget(focus, hit, activityFrame)
        end
    end
    return hit:IsMouseOver()
end
Case.PointerOnSlot = PointerOnSlot

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
Case.FadeCaption = FadeCaption

-- Keeps the slot above Blizzard's reward glow scene.
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
Case.RaiseAboveGlow = RaiseAboveGlow

-- The slot's own face (Blizzard's reward card), which the gates show.
local function FaceAtlas(activityFrame)
    local atlas = DEFAULT_ATLAS
    local bg = activityFrame and activityFrame.Background
    if type(bg) == "table" and type(bg.GetAtlas) == "function" then
        local current = bg:GetAtlas()
        if type(current) == "string" and current ~= "" then
            atlas = current
        end
    end
    return atlas
end
Case.FaceAtlas = FaceAtlas

-- --- the case's frames ---------------------------------------------------------------------------------

local function MakeGate(fx, activityFrame, anchor)
    local gate = CreateFrame("Frame", nil, activityFrame)
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
    local face = gate:CreateTexture(nil, "ARTWORK")
    face:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
    face:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
    if face.SetAtlas then
        face:SetAtlas(DEFAULT_ATLAS)
    else
        ColorTexture(face, 0.12, 0.10, 0.08, 1)
    end
    gate.face = face
    gate:Hide()
    return gate
end

local function MakeSeam(activityFrame)
    local seam = CreateFrame("Frame", nil, activityFrame)
    seam:SetHeight(2)
    seam:EnableMouse(false)
    local line = seam:CreateTexture(nil, "OVERLAY")
    line:SetAllPoints()
    ColorTexture(line, 0.62, 0.48, 0.28, 1)
    seam.line = line
    seam:Hide()
    return seam
end

local function EnsureFX(activityFrame)
    if activityFrame.bgvFX then
        return activityFrame.bgvFX
    end

    local fx = CreateFrame("Frame", nil, activityFrame)
    fx:SetPoint("TOPLEFT", activityFrame, "TOPLEFT", 0, 0)
    fx:SetPoint("BOTTOMRIGHT", activityFrame, "BOTTOMRIGHT", 0, 0)
    fx:EnableMouse(false)
    if fx.SetClipsChildren then
        fx:SetClipsChildren(true)
    end
    fx.owner = activityFrame

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
    fx.shade = shade

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

    -- Between the reel and the gates: light and lines over the items.
    local mid = CreateFrame("Frame", nil, fx)
    mid:SetAllPoints(fx)
    mid:EnableMouse(false)
    fx.mid = mid
    -- Above the gates, clipped to the slot: a style's own art. A frame beside the gates, not inside
    -- the case: the game draws everything inside a clipping frame with it, under the gates whatever
    -- its own level. It shows and hides with the case (ShowCase).
    local top = CreateFrame("Frame", nil, activityFrame)
    top:SetAllPoints(fx)
    top:EnableMouse(false)
    if top.SetClipsChildren then
        top:SetClipsChildren(true)
    end
    top:Hide()
    fx.top = top

    fx.topDoor = MakeGate(fx, activityFrame, "TOP")
    fx.bottomDoor = MakeGate(fx, activityFrame, "BOTTOM")

    -- The marker: over the reel but inside the case, so the gates, the pieces they break into and
    -- every effect are drawn over it (the case draws its contents with it, under what's beside it).
    local marker = CreateFrame("Frame", nil, fx)
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

    fx.topSeam = MakeSeam(activityFrame)
    fx.bottomSeam = MakeSeam(activityFrame)

    fx.offset = 0
    fx.cursor = 1
    fx.phase = "closed"
    fx.t = 0
    fx.pulse = 0
    fx.hop = 0
    fx:Hide()
    activityFrame.bgvFX = fx
    return fx
end
Case.Ensure = EnsureFX

-- The case and its art layer above the gates, shown or hidden together.
local function ShowCase(fx, shown)
    fx:SetShown(shown)
    fx.top:SetShown(shown)
end

local function SlotSize(fx)
    local w, h = fx:GetWidth(), fx:GetHeight()
    if not w or w < 10 then
        w = fx.slotWidth or SLOT_W
    end
    if not h or h < 10 then
        h = fx.slotHeight or SLOT_H
    end
    fx.slotWidth, fx.slotHeight = w, h
    local ww = fx.window:GetWidth()
    if not ww or ww < 10 then
        ww = w - REEL_LEFT - REEL_RIGHT
    end
    fx.windowWidth = ww
    return w, h
end

-- Frame levels: the reel, then light over it, then the gates (or the gates under everything, for
-- the styles that open a hole in the face), then a style's art, then its effects.
local function Levels(fx, doorsBelow)
    local activityFrame = fx.owner
    local level = activityFrame:GetFrameLevel() + 2
    if type(activityFrame.ItemFrame) == "table" and type(activityFrame.ItemFrame.GetFrameLevel) == "function" then
        level = math.max(level, activityFrame.ItemFrame:GetFrameLevel() + 1)
    end
    fx.level = level
    fx:SetFrameLevel(level)
    fx.window:SetFrameLevel(level + 1)
    fx.reel:SetFrameLevel(level + 1)
    for _, cell in ipairs(fx.cells) do
        cell:SetFrameLevel(level + 1)
    end
    fx.marker:SetFrameLevel(level + 2)
    fx.mid:SetFrameLevel(level + 4)
    local doorLevel = doorsBelow and (level - 1) or (level + 8)
    fx.topDoor:SetFrameLevel(doorLevel)
    fx.bottomDoor:SetFrameLevel(doorLevel)
    fx.top:SetFrameLevel(level + 9)
    fx.topSeam:SetFrameLevel(level + 9)
    fx.bottomSeam:SetFrameLevel(level + 9)
    if fx.parts then
        fx.parts.layer:SetFrameLevel(level + 14)
    end
    if activityFrame.bgvText then
        activityFrame.bgvText:SetFrameLevel(level + 8)
    end
    if activityFrame.bgvHit then
        activityFrame.bgvHit:SetFrameLevel(level + 10)
    end
end

-- --- the gates -------------------------------------------------------------------------------------

-- How the face sits in the gates: "wipe" (still, the gates shrink over it), "slide" (each half
-- rides its gate's edge), "shutter" (all of it in the top gate, moved by the style) and "squash"
-- (centred, sized by the style).
local function FaceMode(fx, mode)
    if fx.faceMode == mode then
        return
    end
    fx.faceMode = mode
    local w, h = SlotSize(fx)
    local top, bottom = fx.topDoor.face, fx.bottomDoor.face
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if mode == "slide" and fx.gateLayout == "columns" then
        top:SetPoint("TOPLEFT", fx.topDoor, "TOPRIGHT", -w / 2, 0)
        top:SetSize(w, h)
        bottom:SetPoint("TOPRIGHT", fx.bottomDoor, "TOPLEFT", w / 2, 0)
        bottom:SetSize(w, h)
    elseif mode == "slide" then
        top:SetPoint("TOPLEFT", fx.topDoor, "BOTTOMLEFT", 0, h / 2)
        top:SetPoint("TOPRIGHT", fx.topDoor, "BOTTOMRIGHT", 0, h / 2)
        top:SetHeight(h)
        bottom:SetPoint("BOTTOMLEFT", fx.bottomDoor, "TOPLEFT", 0, -h / 2)
        bottom:SetPoint("BOTTOMRIGHT", fx.bottomDoor, "TOPRIGHT", 0, -h / 2)
        bottom:SetHeight(h)
    elseif mode == "shutter" then
        top:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        top:SetHeight(h)
        bottom:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
    elseif mode == "squash" then
        for _, face in ipairs({ top, bottom }) do
            face:SetPoint("CENTER", fx, "CENTER", 0, 0)
            face:SetSize(w, h)
        end
    else
        for _, face in ipairs({ top, bottom }) do
            face:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
            face:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
        end
    end
end

-- One gate covering `cover` of the slot from its edge (none: hidden). Styles set the gates every
-- frame, mostly to what they already are, so only what changed is set. Every change of a gate's
-- size or showing goes through here (GateLayout forgets what was set), which keeps that true.
local function SetGate(gate, cover, across)
    if cover > 0.01 then
        if gate.cover ~= cover then
            if across then
                gate:SetWidth(cover)
            else
                gate:SetHeight(cover)
            end
        end
        if not (gate.cover and gate.cover > 0.01) then
            gate:Show()
        end
    elseif gate.cover == nil or gate.cover > 0.01 then
        gate:Hide()
    end
    gate.cover = cover
end

-- How much of the slot each gate covers, from its own edge: the top and bottom gates (in
-- "columns", the left and right ones; in "right", one gate from the right edge).
local function Doors(fx, topCover, bottomCover)
    local across = fx.gateLayout == "columns" or fx.gateLayout == "right"
    SetGate(fx.topDoor, topCover, across)
    SetGate(fx.bottomDoor, bottomCover, across)
end

-- Where the gates hang: "rows" (top and bottom, the usual), "columns" (left and right) or
-- "right" (one gate over the slot from its right edge; the other unused).
local function GateLayout(fx, layout)
    layout = layout or "rows"
    if (fx.gateLayout or "rows") == layout then
        return
    end
    fx.gateLayout = layout
    local top, bottom = fx.topDoor, fx.bottomDoor
    top:ClearAllPoints()
    bottom:ClearAllPoints()
    if layout == "columns" then
        top:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        top:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
    elseif layout == "right" then
        top:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        top:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
        bottom:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
    else
        top:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, 0)
        top:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, 0)
        bottom:SetPoint("BOTTOMLEFT", fx, "BOTTOMLEFT", 0, 0)
        bottom:SetPoint("BOTTOMRIGHT", fx, "BOTTOMRIGHT", 0, 0)
    end
    -- the faces sit by the gates' edges: placed again for the new layout; the gates' sizes too
    fx.faceMode = nil
    top.cover, bottom.cover = nil, nil
end

local function DoorsClosed(fx)
    local w, h = SlotSize(fx)
    if fx.gateLayout == "columns" then
        Doors(fx, w / 2, w / 2)
    elseif fx.gateLayout == "right" then
        Doors(fx, w, 0)
    else
        Doors(fx, h / 2, h / 2)
    end
end

-- The gates' face tinted (1, 1, 1: as it is), and grey when `grey`: the gates catching a style's
-- light, heat or rot. Rest puts it back.
local function FaceTint(fx, r, g, b, grey)
    -- styles tint every frame, mostly the same; Prepare forgets it for each opening
    grey = grey == true
    if fx.tintR == r and fx.tintG == g and fx.tintB == b and fx.tintGrey == grey then
        return
    end
    fx.tintR, fx.tintG, fx.tintB, fx.tintGrey = r, g, b, grey
    local top, bottom = fx.topDoor.face, fx.bottomDoor.face
    top:SetVertexColor(r, g, b)
    bottom:SetVertexColor(r, g, b)
    if top.SetDesaturated then
        top:SetDesaturated(grey)
        bottom:SetDesaturated(grey)
    end
    fx.faceTinted = true
end

-- The seams along the gates' inner edges, `top` and `bottom` from the slot's edges (nil: none).
-- Only Seams moves them, so it skips what's already so.
local function Seams(fx, top, bottom)
    if fx.seamTop == top and fx.seamBottom == bottom then
        return
    end
    fx.seamTop, fx.seamBottom = top, bottom
    if top then
        fx.topSeam:ClearAllPoints()
        fx.topSeam:SetPoint("LEFT", fx, "TOPLEFT", REEL_LEFT, -top)
        fx.topSeam:SetPoint("RIGHT", fx, "TOPRIGHT", -REEL_RIGHT, -top)
        fx.topSeam:Show()
        fx.bottomSeam:ClearAllPoints()
        fx.bottomSeam:SetPoint("LEFT", fx, "BOTTOMLEFT", REEL_LEFT, bottom)
        fx.bottomSeam:SetPoint("RIGHT", fx, "BOTTOMRIGHT", -REEL_RIGHT, bottom)
        fx.bottomSeam:Show()
    else
        fx.topSeam:Hide()
        fx.bottomSeam:Hide()
    end
end

-- A rattle: the case (and everything anchored to it) jolts, fading as `fx.shake` runs down.
local function Shake(fx, dt)
    local amount = fx.shake or 0
    if amount <= 0 then
        return
    end
    amount = math.max(0, amount - dt * 7)
    fx.shake = amount
    local x, y = 0, 0
    if amount > 0 then
        local time = Now()
        x, y = math.sin(time * 97) * amount, math.cos(time * 83) * amount * 0.6
    end
    fx:ClearAllPoints()
    fx:SetPoint("TOPLEFT", fx.owner, "TOPLEFT", x, y)
    fx:SetPoint("BOTTOMRIGHT", fx.owner, "BOTTOMRIGHT", x, y)
end

local function ClearShake(fx)
    fx.shake = 0
    fx:ClearAllPoints()
    fx:SetPoint("TOPLEFT", fx.owner, "TOPLEFT", 0, 0)
    fx:SetPoint("BOTTOMRIGHT", fx.owner, "BOTTOMRIGHT", 0, 0)
end

-- --- the marker ------------------------------------------------------------------------------------

local function MarkerTint(fx, r, g, b)
    ColorTexture(fx.markerLine, r, g, b, 0.95)
    if fx.markerGlow then
        fx.markerGlow:SetVertexColor(r, g, b)
    end
end

local function ColorMarker(fx)
    local color = Utils.AccentColor()
    MarkerTint(fx, color[1], color[2], color[3])
    for _, seam in ipairs({ fx.topSeam, fx.bottomSeam }) do
        ColorTexture(seam.line, 0.62, 0.48, 0.28, 1)
    end
end

local function EnsureMarkerGlow(fx)
    if not fx.markerGlow then
        local glow = fx.marker:CreateTexture(nil, "OVERLAY", nil, -1)
        glow:SetTexture(MEDIA .. "CaseGlow")
        glow:SetBlendMode("ADD")
        glow:SetPoint("TOP", fx.marker, "TOP", 0, 0)
        glow:SetPoint("BOTTOM", fx.marker, "BOTTOM", 0, 0)
        glow:SetWidth(18)
        glow:SetAlpha(0)
        fx.markerGlow = glow
        ColorMarker(fx)
    end
    return fx.markerGlow
end

-- --- the reel -------------------------------------------------------------------------------------

local function TierColor(entry)
    if not (BGV.Bis and Utils.ShowBisTiers()) then
        return nil
    end
    local itemID = type(entry) == "table" and entry.itemID or nil
    local tier = itemID and BGV.Bis.Tier(itemID, Utils.LootSpecID()) or nil
    return tier and TIER_BACK[tier] or nil
end

local function PaintReel(fx)
    local icons = fx.icons
    if type(icons) ~= "table" or #icons == 0 then
        -- Nothing loaded yet (e.g. right after a loot spec change): show an empty reel rather
        -- than the previous list's icons.
        for _, cell in ipairs(fx.cells or {}) do
            cell.icon:SetTexture(nil)
            cell.hasIcon = false
            cell.back:Hide()
            if cell.ghosts then
                for _, ghost in ipairs(cell.ghosts) do
                    ghost:SetTexture(nil)
                end
            end
        end
        return
    end
    local showTiers = BGV.Bis and Utils.ShowBisTiers()
    local specID = showTiers and Utils.LootSpecID() or nil
    for index, cell in ipairs(fx.cells) do
        local item = fx.cursor + index - 1
        local entry = (fx.landItem == item and fx.landEntry) or icons[((item - 1) % #icons) + 1]
        local itemID = type(entry) == "table" and entry.itemID or nil
        local icon = type(entry) == "table" and entry.icon or entry
        cell.icon:SetTexture(icon)
        cell.hasIcon = icon ~= nil
        if cell.ghosts then
            for _, ghost in ipairs(cell.ghosts) do
                ghost:SetTexture(icon)
            end
        end
        local tier = itemID and showTiers and BGV.Bis.Tier(itemID, specID) or nil
        local color = tier and TIER_BACK[tier] or nil
        if color then
            ColorTexture(cell.back, color[1], color[2], color[3], 1)
            cell.back:Show()
        else
            cell.back:Hide()
        end
    end
end
Case.PaintReel = PaintReel

local function PlaceReel(fx)
    fx.reel:ClearAllPoints()
    fx.reel:SetPoint("TOPLEFT", fx.window, "TOPLEFT", fx.offset or 0, 0)
    fx.reel:SetPoint("BOTTOMLEFT", fx.window, "BOTTOMLEFT", fx.offset or 0, 0)
end
Case.PlaceReel = PlaceReel

-- Moves the reel `distance` to the left (negative: right), wrapping its cells, and notes when a
-- new item reaches the marker (the marker's pulse, an item's hop).
local function MoveReelBy(fx, distance)
    if type(fx.icons) ~= "table" or #fx.icons == 0 then
        return
    end
    local offset = (fx.offset or 0) - distance
    local cursor = fx.cursor or 1
    local wrapped = false
    while offset <= -CASE_STRIDE do
        offset = offset + CASE_STRIDE
        cursor = cursor + 1
        wrapped = true
    end
    while offset > 0 do
        offset = offset - CASE_STRIDE
        cursor = cursor - 1
        wrapped = true
    end
    fx.offset, fx.cursor = offset, cursor
    if wrapped then
        PaintReel(fx)
    end
    PlaceReel(fx)
    local marker = (fx.windowWidth or (SLOT_W - REEL_LEFT - REEL_RIGHT)) / 2 + 1
    local item = cursor + math.floor((marker - offset) / CASE_STRIDE)
    if fx.markerItem ~= item then
        if fx.markerItem then
            fx.pulse = 1
            fx.hop = 1
            fx.hopItem = item
        end
        fx.markerItem = item
    end
end

-- The reward's reel slows from CLAIM_SPIN to a stop (a cubic ease, starting at the spin's own
-- speed), the reward painted into the item that stops at the marker.
local function StartLanding(fx)
    local marker = (fx.windowWidth or (SLOT_W - REEL_LEFT - REEL_RIGHT)) / 2 + 1
    -- where the reel is, counted in items: item k is centred on the marker when this is k
    local at = (fx.cursor or 1) + (marker - (fx.offset or 0)) / CASE_STRIDE - 0.5
    local item = math.ceil(at) + CLAIM_PASS
    local distance = (item - at) * CASE_STRIDE
    fx.landItem = item
    fx.landEntry = fx.claim
    fx.land = { distance = distance, done = 0, t = 0, length = 3 * distance / CLAIM_SPIN }
    PaintReel(fx)
end

local function MoveClaimReel(fx, dt)
    -- the main reel lands once (landItem); a style with reels of its own (the One-Armed Bandit)
    -- may have revealed the reward without it
    if not fx.land and not fx.landItem then
        if fx.phase ~= "open" or type(fx.icons) ~= "table" or #fx.icons == 0 then
            fx.reelSpeed = CLAIM_SPIN
            MoveReelBy(fx, CLAIM_SPIN * dt)
            return
        end
        StartLanding(fx)
    end
    local land = fx.land
    if not land then
        fx.reelSpeed = 0
        return
    end
    land.t = land.t + dt
    local k = Clamp01(land.t / land.length)
    local goal = land.distance * (1 - (1 - k) ^ 3)
    MoveReelBy(fx, goal - land.done)
    fx.reelSpeed = (goal - land.done) / math.max(dt, 0.001)
    land.done = goal
    if k >= 1 then
        fx.land = nil
        fx.landedAt = fx.landedAt or Now()
        fx.reelSpeed = 0
    end
end

-- The reel at a style's `speed`; a reward's reel (Case.OpenClaim) goes its own way.
local function MoveReel(fx, speed, dt)
    if fx.claim then
        MoveClaimReel(fx, dt)
    else
        fx.reelSpeed = speed
        if speed ~= 0 then
            MoveReelBy(fx, speed * dt)
        end
    end
    fx.pulse = math.max(0, (fx.pulse or 0) - dt * 3.5)
    fx.hop = math.max(0, (fx.hop or 0) - dt * 3)
end

local function EnsureGhosts(fx)
    for _, cell in ipairs(fx.cells) do
        if not cell.ghosts then
            cell.ghosts = {}
            for n = 1, 2 do
                local ghost = cell:CreateTexture(nil, "ARTWORK", nil, -1)
                ghost:SetSize(CASE_ICON, CASE_ICON)
                ghost:SetPoint("CENTER", cell, "CENTER", 0, 0)
                ghost:SetTexture(cell.icon:GetTexture())
                ghost:Hide()
                cell.ghosts[n] = ghost
            end
        end
    end
end

-- The reel's items dressed for a style: `zoom` grows the one at the marker, `ghosts` trails blur
-- at speed, `hop` bounces each item as it reaches the marker, `bob` floats them, `shimmer` is heat.
local function DressCells(fx, zoom, ghosts, hop, bob, shimmer)
    local marker = (fx.windowWidth or (SLOT_W - REEL_LEFT - REEL_RIGHT)) / 2 + 1
    local speed = fx.reelSpeed or 0
    local time = Now()
    local trail = 0
    if ghosts then
        trail = Clamp01((math.abs(speed) - 260) / 700)
    end
    -- a reward landed at the marker (Case.OpenClaim): it grows and the rest dims
    local focus = fx.landedAt and Clamp01((time - fx.landedAt) / CLAIM_GROW) or 0
    fx.dressed = true
    local windowWidth = fx.windowWidth or (SLOT_W - REEL_LEFT - REEL_RIGHT)
    for index, cell in ipairs(fx.cells) do
        local center = (fx.offset or 0) + (index - 0.5) * CASE_STRIDE
        -- the cells go left to right: past here (a stride's margin for the blur trails) none shows
        if center - CASE_STRIDE >= windowWidth then
            break
        end
        local near = 1 - math.abs(center - marker) / CASE_STRIDE
        if near < 0 then
            near = 0
        end
        local sx = 1 + zoom * near
        local sy, dy = sx, 0
        local item = (fx.cursor or 1) + index - 1
        if hop and (fx.hop or 0) > 0 and item == fx.hopItem then
            local k = math.sin((1 - fx.hop) * math.pi)
            sy = sy * (1 + 0.2 * k)
            sx = sx * (1 - 0.12 * k)
            dy = 6 * k
        end
        if bob > 0 then
            dy = dy + math.sin(time * 2.2 + item * 1.3) * bob
        end
        if shimmer > 0 then
            dy = dy + math.sin(time * 9 + item * 2.1) * shimmer
        end
        local alpha = 1
        if focus > 0 then
            if item == fx.landItem then
                sx = 1 + CLAIM_ZOOM * EaseOutBack(focus, 1.7)
                sy, dy = sx, CLAIM_LIFT * EaseOutCubic(focus)
            else
                alpha = 1 - 0.72 * focus
            end
        end
        if cell.dressA ~= alpha then
            cell:SetAlpha(alpha)
            cell.dressA = alpha
        end
        -- only what changed: most items sit still in size, and ghosts show only at speed
        local w, h = CASE_ICON * sx, CASE_ICON * sy
        if cell.dressW ~= w or cell.dressH ~= h then
            cell.icon:SetSize(w, h)
            cell.dressW, cell.dressH = w, h
        end
        if cell.dressY ~= dy then
            cell.icon:SetPoint("CENTER", cell, "CENTER", 0, dy)
            cell.dressY = dy
        end
        if cell.ghosts then
            if trail > 0 and cell.hasIcon then
                for n, ghost in ipairs(cell.ghosts) do
                    ghost:SetSize(w, h)
                    ghost:SetPoint("CENTER", cell, "CENTER", n * speed * 0.011, dy)
                    ghost:SetAlpha(0.3 * trail / n)
                    ghost:Show()
                end
                cell.ghostsShown = true
            elseif cell.ghostsShown then
                for _, ghost in ipairs(cell.ghosts) do
                    ghost:Hide()
                end
                cell.ghostsShown = false
            end
        end
    end
end

-- The reel's items back to how they are at rest: only what changed (the case rests often, and
-- only DressCells and ResetCells size, place, fade and trail them, keeping track as they do).
local function ResetCells(fx)
    for _, cell in ipairs(fx.cells) do
        if cell.dressA ~= 1 then
            cell:SetAlpha(1)
            cell.dressA = 1
        end
        if cell.dressW ~= CASE_ICON or cell.dressH ~= CASE_ICON then
            cell.icon:SetSize(CASE_ICON, CASE_ICON)
            cell.dressW, cell.dressH = CASE_ICON, CASE_ICON
        end
        if cell.dressY ~= 0 then
            cell.icon:SetPoint("CENTER", cell, "CENTER", 0, 0)
            cell.dressY = 0
        end
        cell.back:SetAlpha(1)
        if cell.ghostsShown then
            for _, ghost in ipairs(cell.ghosts) do
                ghost:Hide()
            end
            cell.ghostsShown = false
        end
    end
end

local function CellBacksAlpha(fx, alpha)
    for _, cell in ipairs(fx.cells) do
        cell.back:SetAlpha(alpha)
    end
end

-- The loot list was still loading when the case opened (a loot spec change clears it): keep
-- asking while it's open, so the reel fills in and scrolls without pointing at it again.
local function RefreshIcons(fx, dt)
    local slot = fx.owner and fx.owner.bgvSlot
    if not (fx.iconsPending and fx.want and slot) then
        return
    end
    fx.refreshClock = (fx.refreshClock or 0) + dt
    -- Nothing to show yet: check more often, so items appear soon after they load.
    if fx.refreshClock < ((fx.iconCount or 0) == 0 and REEL_REFRESH_EMPTY or REEL_REFRESH) then
        return
    end
    fx.refreshClock = 0
    local icons, pending = BGV.Rewards.PossibleIcons(slot)
    fx.iconsPending = pending == true
    if type(icons) == "table" and (icons ~= fx.iconKey or #icons ~= fx.iconCount) then
        fx.icons = icons
        fx.iconKey = icons
        fx.iconCount = #icons
        if #icons > 0 and not fx.reelReady then
            fx.cursor = math.random(#icons)
            fx.offset = 0
            fx.reelReady = true
        end
        PaintReel(fx)
        PlaceReel(fx)
    end
end

-- --- effects: one pool of textures per slot, reused ------------------------------------------------------

-- Clouds come in four shapes side by side (`shapes`), and each one is mirrored at random, tilted
-- up to `tilt` radians, turns up to `turn` a second as it drifts, and is up to `stretch` wider or
-- narrower, so no two look alike.
local KINDS = {
    dust = { file = MEDIA .. "CasePuffs", blend = "BLEND", shapes = 4, tilt = 0.5, turn = 0.8, stretch = 0.2 },
    ink = { file = MEDIA .. "CaseInkPuffs", blend = "BLEND", shapes = 4, tilt = 0.3, turn = 0.5, stretch = 0.15 },
    sparkle = { file = MEDIA .. "CaseSparkle", blend = "ADD", spin = true },
    ember = { file = MEDIA .. "CaseGlow", blend = "ADD" },
    coin = { file = MEDIA .. "CaseCoin", blend = "BLEND", flip = true },
    ash = { file = WHITE, blend = "BLEND", spin = true },
}

local function EnsureParticles(fx)
    local parts = fx.parts
    if parts then
        return parts
    end
    local layer = CreateFrame("Frame", nil, fx.owner)
    layer:SetAllPoints(fx.owner)
    layer:EnableMouse(false)
    layer:SetFrameLevel((fx.level or fx.owner:GetFrameLevel()) + 14)
    parts = { layer = layer, live = 0 }
    for index = 1, PARTICLES do
        local texture = layer:CreateTexture(nil, "OVERLAY")
        texture:Hide()
        parts[index] = { texture = texture, live = false }
    end
    fx.parts = parts
    return parts
end

-- One effect at (x, y) from the slot's centre (up is +y), moving (vx, vy) a second, for `life`
-- seconds, `size` across. Returns it so the caller can set the rest (g, drag, grow, spin, alpha,
-- late, the texture's color), or nil while the pool is all in use.
local function Spawn(fx, kind, x, y, vx, vy, life, size)
    -- played out of sight in one go (Case.ShowClaims): an effect would be gone before it was seen
    if fx.playingOut then
        return nil
    end
    local parts = EnsureParticles(fx)
    for index = 1, PARTICLES do
        local p = parts[index]
        if not p.live then
            local look = KINDS[kind]
            p.live = true
            p.x, p.y, p.vx, p.vy, p.life, p.size, p.age = x, y, vx, vy, life, size, 0
            p.g, p.drag, p.grow, p.spin, p.rot, p.alpha, p.late = 0, 1, 0.8, 0, 0, 1, false
            -- flags stay booleans: a field set to nil and back makes the table grow again
            p.flip, p.turns, p.aspect, p.align = look.flip == true, look.spin == true, 1, look.align == true
            local texture = p.texture
            if p.file ~= look.file then
                texture:SetTexture(look.file)
                p.file = look.file
            end
            if look.shapes then
                local shape = math.random(look.shapes)
                local left, right = (shape - 1) / look.shapes, shape / look.shapes
                if math.random() < 0.5 then
                    left, right = right, left
                end
                texture:SetTexCoord(left, right, 0, 1)
                p.rot = Random(-look.tilt, look.tilt)
                p.spin = Random(-look.turn, look.turn)
                p.aspect = 1 + Random(-look.stretch, look.stretch)
                p.turns = true
            else
                texture:SetTexCoord(0, 1, 0, 1)
            end
            texture:SetBlendMode(look.blend)
            texture:SetVertexColor(1, 1, 1, 1)
            texture:SetRotation(p.rot)
            texture:SetSize(size * p.aspect, size)
            texture:SetPoint("CENTER", fx, "CENTER", x, y)
            texture:SetAlpha(1)
            texture:Show()
            parts.live = parts.live + 1
            return p
        end
    end
end

local function UpdateParticles(fx, dt)
    local parts = fx.parts
    if not parts or parts.live == 0 then
        return
    end
    for index = 1, PARTICLES do
        local p = parts[index]
        if p.live then
            p.age = p.age + dt
            if p.age >= p.life then
                p.live = false
                parts.live = parts.live - 1
                p.texture:Hide()
            else
                if p.drag ~= 1 then
                    local keep = p.drag ^ (dt * 60)
                    p.vx, p.vy = p.vx * keep, p.vy * keep
                end
                p.vy = p.vy + p.g * dt
                p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
                local life = p.age / p.life
                local size = p.size * (1 + p.grow * EaseOutCubic(life))
                local width = size * p.aspect
                if p.align then
                    -- a streak, pointing along its flight
                    p.texture:SetRotation(atan2(p.vy, p.vx))
                elseif p.spin ~= 0 then
                    p.rot = p.rot + p.spin * dt
                    if p.flip then
                        width = size * (math.abs(math.cos(p.rot)) + 0.12)
                    elseif p.turns then
                        p.texture:SetRotation(p.rot)
                    end
                end
                p.texture:SetSize(width, size)
                p.texture:SetPoint("CENTER", fx, "CENTER", p.x, p.y)
                local fade = p.late and (life > 0.8 and (1 - life) / 0.2 or 1) or (1 - life * life)
                p.texture:SetAlpha(p.alpha * fade)
            end
        end
    end
end

local function ClearParticles(fx)
    local parts = fx.parts
    if not parts then
        return
    end
    for index = 1, PARTICLES do
        local p = parts[index]
        if p.live then
            p.live = false
            p.texture:Hide()
        end
    end
    parts.live = 0
end

-- --- the portal and iris: a circle the reel shows through ----------------------------------------------------

local function EnsureCircle(fx)
    if not fx.circle then
        local mask = fx:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetPoint("CENTER", fx, "CENTER", 0, 0)
        mask:SetSize(1, 1)
        fx.circle = mask
        fx.circleFile = CIRCLE_MASK
        fx.masked = {}
        fx.maskedSet = {}
    end
    return fx.circle
end

local function MaskAdd(fx, texture)
    if texture and not fx.maskedSet[texture] then
        texture:AddMaskTexture(fx.circle)
        fx.masked[#fx.masked + 1] = texture
        fx.maskedSet[texture] = true
    end
end

-- The reel, its marker and the style's `...` textures show only inside the circle.
local function MaskOn(fx, ...)
    EnsureCircle(fx)
    EnsureMarkerGlow(fx)
    MaskAdd(fx, fx.shade)
    for _, cell in ipairs(fx.cells) do
        MaskAdd(fx, cell.back)
        MaskAdd(fx, cell.icon)
    end
    MaskAdd(fx, fx.markerLine)
    MaskAdd(fx, fx.markerGlow)
    for index = 1, select("#", ...) do
        MaskAdd(fx, (select(index, ...)))
    end
end

local function MaskOff(fx)
    if fx.cut then
        fx.cut = false
        fx.topDoor.face:RemoveMaskTexture(fx.topDoor.cut)
        fx.bottomDoor.face:RemoveMaskTexture(fx.bottomDoor.cut)
    end
    if not fx.masked then
        return
    end
    for index = #fx.masked, 1, -1 do
        local texture = fx.masked[index]
        texture:RemoveMaskTexture(fx.circle)
        fx.masked[index] = nil
        fx.maskedSet[texture] = nil
    end
end

-- The circle (or shape) at (x, y) from the slot's centre. Styles set it every frame, mostly as it
-- is; only MaskCircle sizes and places it, so it skips what's already so.
local function MaskCircle(fx, x, y, radius, radiusY)
    local circle = fx.circle
    local w, h = math.max(1, 2 * radius), math.max(1, 2 * (radiusY or radius))
    if circle.bgvW ~= w or circle.bgvH ~= h then
        circle:SetSize(w, h)
        circle.bgvW, circle.bgvH = w, h
        if fx.cut then
            local scale = fx.cutScale
            fx.topDoor.cut:SetSize(w * scale, h * scale)
            fx.bottomDoor.cut:SetSize(w * scale, h * scale)
        end
    end
    if circle.bgvX ~= x or circle.bgvY ~= y then
        circle:SetPoint("CENTER", fx, "CENTER", x, y)
        circle.bgvX, circle.bgvY = x, y
        if fx.cut then
            fx.topDoor.cut:SetPoint("CENTER", fx, "CENTER", x, y)
            fx.bottomDoor.cut:SetPoint("CENTER", fx, "CENTER", x, y)
        end
    end
end

-- The hole through the gates. A style that opens a hole keeps the gates shut under the reel, and
-- the reel shows only in its window, so round the window (the slot's edges) the gates would stay
-- once it's open. So each gate's face is cut too, by the hole's inverse (white, the hole clear),
-- sized and placed with the hole (MaskCircle); outside it the gates show (CLAMPTOWHITE). A shape's
-- inverse is "<shape>Cut"; the circle's has a margin round it, so it's drawn that much larger.
local CIRCLE_CUT, CIRCLE_CUT_SCALE = MEDIA .. "CaseCircleCut", 64 / 60

local function CutGate(fx, gate, file, w, h)
    local cut = gate.cut
    if not cut then
        cut = gate:CreateMaskTexture()
        gate.cut = cut
    end
    if gate.cutFile ~= file then
        cut:SetTexture(file, "CLAMPTOWHITE", "CLAMPTOWHITE")
        gate.cutFile = file
    end
    cut:SetSize(w, h)
    cut:SetPoint("CENTER", fx, "CENTER", fx.circle.bgvX or 0, fx.circle.bgvY or 0)
    if not fx.cut then
        gate.face:AddMaskTexture(cut)
    end
end

-- Cuts the hole through the gates as well, from now until the style rests (MaskOff).
local function CutGates(fx)
    local circle = EnsureCircle(fx)
    local file, scale = fx.circleFile .. "Cut", 1
    if fx.circleFile == CIRCLE_MASK then
        file, scale = CIRCLE_CUT, CIRCLE_CUT_SCALE
    end
    local w, h = (circle.bgvW or 1) * scale, (circle.bgvH or 1) * scale
    CutGate(fx, fx.topDoor, file, w, h)
    CutGate(fx, fx.bottomDoor, file, w, h)
    fx.cut, fx.cutScale = true, scale
end

-- The hole's shape: a mask file (white, the shape in alpha), or nil for the circle.
local function MaskShape(fx, file)
    EnsureCircle(fx)
    file = file or CIRCLE_MASK
    if fx.circleFile ~= file then
        fx.circle:SetTexture(file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        fx.circleFile = file
        if fx.cut then
            CutGates(fx)
        end
    end
end

-- What every style leaves behind when the slot closes: the gates shut over the full face, and
-- the reel and marker as they were.
local function RestCommon(fx)
    MaskOff(fx)
    if fx.faceTinted then
        FaceTint(fx, 1, 1, 1, false)
        fx.faceTinted = false
    end
    if fx.circle then
        MaskShape(fx, nil)
    end
    ClearShake(fx)
    GateLayout(fx, "rows")
    FaceMode(fx, "wipe")
    Levels(fx, false)
    fx.topDoor:SetAlpha(1)
    fx.bottomDoor:SetAlpha(1)
    DoorsClosed(fx)
    Seams(fx, nil)
    ResetCells(fx)
    ColorTexture(fx.shade, 0.02, 0.015, 0.01, 1)
    fx.shade:SetAlpha(1)
    fx.window:Show()
    if fx.markerGlow then
        fx.markerGlow:SetAlpha(0)
    end
    ColorMarker(fx)
end

-- How much each gate covers once `reveal` (0 to 1) of the reel shows (the slot was measured as the
-- case opened, Prepare).
local function GateCover(fx, reveal)
    local h = fx.slotHeight or SLOT_H
    return math.min(h / 2, GATE_CORNER + (h / 2 - GATE_CORNER) * (1 - reveal))
end

local function Dust(fx, x, y, vx, vy, life, size, alpha)
    local p = Spawn(fx, "dust", x, y, vx, vy, life, size)
    if p then
        p.drag = 0.93
        p.alpha = alpha or 0.75
        p.texture:SetVertexColor(0.81, 0.76, 0.66)
    end
    return p
end

-- --- Classic: the gates wipe open over half a second (1.0's look) -------------------------------------------

STYLE.classic = {
    openFor = 0.5,
    closeFor = 0.5,
    reversible = true,
    Enter = function(fx)
        Levels(fx, false)
        FaceMode(fx, "wipe")
    end,
    Update = function(fx, dt)
        local reveal
        if fx.phase == "opening" then
            reveal = Smooth(fx.t / 0.5)
        elseif fx.phase == "open" then
            reveal = 1
        else
            reveal = 1 - Smooth(fx.t / 0.5)
        end
        local cover = GateCover(fx, reveal)
        Doors(fx, cover, cover)
        Seams(fx, cover, cover)
        MoveReel(fx, reveal > 0 and 100 or 0, dt)
    end,
    Rest = RestCommon,
}

-- --- Vault Door: the doors unlatch, slide apart with a little overshoot and slam shut ---------------------------

local function VaultArt(fx)
    local art = fx.vaultArt
    if not art then
        art = {}
        local light = fx.mid:CreateTexture(nil, "OVERLAY")
        light:SetTexture(MEDIA .. "CaseGlow")
        light:SetBlendMode("ADD")
        light:SetVertexColor(1, 0.84, 0.55)
        light:SetPoint("CENTER", fx, "CENTER", 0, 0)
        light:Hide()
        art.light = light
        fx.vaultArt = art
    end
    return art
end

STYLE.vault = {
    openFor = 0.62,
    closeFor = 0.5,
    Enter = function(fx)
        local art = VaultArt(fx)
        Levels(fx, false)
        FaceMode(fx, "slide")
        EnsureGhosts(fx)
        EnsureMarkerGlow(fx)
        art.light:SetSize(fx.windowWidth * 1.3, 64)
        art.light:SetAlpha(0)
        art.light:Show()
        fx.light = 0
    end,
    Update = function(fx, dt)
        local t, flags = fx.t, fx.flags
        local w = fx.slotWidth
        local reveal, gap, speed = 0, 0, 0
        if fx.phase == "opening" then
            if t < 0.1 then
                gap = 3 * math.sin(math.pi * t / 0.1)
            else
                if not flags.unlatched then
                    flags.unlatched = true
                    fx.light, fx.shake = 1, 1.1
                    for n = 0, 8 do
                        local x = -w / 2 + 16 + n * (w - 32) / 8 + Random(-6, 6)
                        Dust(fx, x, Random(-2, 2), (x < 0 and -1 or 1) * Random(12, 48), Random(-26, 26), Random(0.7, 1.05), Random(9, 15))
                    end
                end
                reveal = EaseOutBack((t - 0.1) / 0.52, 2.1)
                speed = 100 + 1000 * math.exp(-(t - 0.1) / 0.3)
            end
        elseif fx.phase == "open" then
            reveal = 1
            speed = 100 + 1000 * math.exp(-(t + 0.52) / 0.3)
        elseif t < 0.26 then
            reveal = 1 - EaseInCubic(t / 0.26)
            speed = 100 * (1 - t / 0.26)
        else
            if not flags.slammed then
                flags.slammed = true
                fx.shake = 2
                for side = -1, 1, 2 do
                    for _ = 1, 3 do
                        Dust(fx, side * (w / 2 - 8), Random(-3, 3), side * Random(40, 90), Random(-18, 18), Random(0.6, 0.9), Random(10, 16), 0.8)
                    end
                end
            end
            local b = Clamp01((t - 0.26) / 0.24)
            gap = 4 * math.sin(math.pi * b) * (1 - b)
        end
        local cover = math.max(0, GateCover(fx, reveal) - gap / 2)
        Doors(fx, cover, cover)
        Seams(fx, cover, cover)
        MoveReel(fx, speed, dt)
        DressCells(fx, 0.16, true, false, 0, 0)
        fx.markerGlow:SetAlpha(fx.pulse * 0.8)
        fx.light = math.max(0, fx.light - dt * 2.2)
        fx.vaultArt.light:SetAlpha(fx.light * 0.75)
        Shake(fx, dt)
    end,
    Rest = function(fx)
        if fx.vaultArt then
            fx.vaultArt.light:Hide()
        end
        RestCommon(fx)
    end,
}

-- --- One-Armed Bandit: the face rolls up onto a slot machine; three reels stop on the payline ---------------------

local BANDIT_W, BANDIT_GAP, BANDIT_STRIDE, BANDIT_CELLS, BULBS = 54, 9, 46, 5, 13

local function BanditArt(fx)
    local art = fx.banditArt
    if art then
        return art
    end
    art = { bulbs = {}, columns = {} }
    local frame = CreateFrame("Frame", nil, fx)
    frame:SetAllPoints(fx)
    frame:EnableMouse(false)
    art.frame = frame
    local cabinet = frame:CreateTexture(nil, "BACKGROUND")
    cabinet:SetAllPoints(fx)
    cabinet:SetTexture(MEDIA .. "CaseCabinet")
    cabinet:SetTexCoord(0, 219 / 256, 0, 126 / 128)
    for row = 0, 1 do
        for index = 1, BULBS do
            local core = frame:CreateTexture(nil, "ARTWORK")
            core:SetTexture(MEDIA .. "CaseBulb")
            core:SetSize(5, 5)
            local halo = frame:CreateTexture(nil, "ARTWORK", nil, 1)
            halo:SetTexture(MEDIA .. "CaseGlow")
            halo:SetBlendMode("ADD")
            halo:SetSize(15, 15)
            art.bulbs[#art.bulbs + 1] = { core = core, halo = halo, row = row, index = index }
        end
    end
    for c = 1, 3 do
        local column = CreateFrame("Frame", nil, frame)
        if column.SetClipsChildren then
            column:SetClipsChildren(true)
        end
        local ivory = column:CreateTexture(nil, "BACKGROUND")
        ivory:SetAllPoints()
        ColorTexture(ivory, 0.94, 0.9, 0.82, 1)
        column.cells = {}
        for k = 1, BANDIT_CELLS do
            local back = column:CreateTexture(nil, "BORDER")
            back:SetSize(44, 44)
            back:Hide()
            local ghost = column:CreateTexture(nil, "ARTWORK", nil, -1)
            ghost:SetSize(CASE_ICON, CASE_ICON)
            ghost:SetAlpha(0.25)
            ghost:Hide()
            local icon = column:CreateTexture(nil, "ARTWORK")
            icon:SetSize(CASE_ICON, CASE_ICON)
            column.cells[k] = { back = back, ghost = ghost, icon = icon }
        end
        local drum = column:CreateTexture(nil, "OVERLAY")
        drum:SetAllPoints()
        drum:SetTexture(MEDIA .. "CaseDrum")
        Utils.Border(column, 0.82, 0.82, 0.82, 1)
        column.seed = (c - 1) * 5
        column.pos, column.speed, column.mode, column.t, column.from, column.dist, column.k = 0, 0, "held", 0, 0, 0, 0
        art.columns[c] = column
    end
    art.payline = frame:CreateTexture(nil, "OVERLAY")
    art.arrows = {}
    for side = 1, 2 do
        local arrow = frame:CreateTexture(nil, "OVERLAY")
        arrow:SetTexture(MEDIA .. "CaseArrow")
        arrow:SetSize(7, 9)
        if side == 2 then
            arrow:SetTexCoord(1, 0, 0, 1)
        end
        art.arrows[side] = arrow
    end
    local slats = fx.topDoor:CreateTexture(nil, "OVERLAY")
    slats:SetTexture(MEDIA .. "CaseSlats", "REPEAT", "REPEAT")
    slats:Hide()
    art.slats = slats
    frame:Hide()
    fx.banditArt = art
    return art
end

local function LayoutBandit(fx, art)
    local w, h = fx.slotWidth, fx.slotHeight
    local ww = fx.windowWidth
    local wh = h - 2 * GATE_CORNER
    local span = 3 * BANDIT_W + 2 * BANDIT_GAP
    local x0 = REEL_LEFT + (ww - span) / 2
    for c, column in ipairs(art.columns) do
        column:ClearAllPoints()
        column:SetPoint("TOPLEFT", fx, "TOPLEFT", x0 + (c - 1) * (BANDIT_W + BANDIT_GAP), -GATE_CORNER)
        column:SetSize(BANDIT_W, wh)
    end
    for _, bulb in ipairs(art.bulbs) do
        local x = 12 + (bulb.index - 1) * (w - 24) / (BULBS - 1)
        local y = bulb.row == 0 and -8 or -(h - 8)
        bulb.core:SetPoint("CENTER", fx, "TOPLEFT", x, y)
        bulb.halo:SetPoint("CENTER", fx, "TOPLEFT", x, y)
    end
    local cx = (REEL_LEFT - REEL_RIGHT) / 2
    art.payline:SetSize(span + 12, 1.5)
    art.payline:SetPoint("CENTER", fx, "CENTER", cx, 0)
    art.arrows[1]:SetPoint("RIGHT", art.payline, "LEFT", 1, 0)
    art.arrows[2]:SetPoint("LEFT", art.payline, "RIGHT", -1, 0)
    art.slats:ClearAllPoints()
    art.slats:SetAllPoints(fx.topDoor.face)
    art.slats:SetTexCoord(0, 1, 0, h / 9)
end

local function PaintBandit(fx, art)
    local icons = fx.icons
    local count = type(icons) == "table" and #icons or 0
    if art.iconKey ~= fx.iconKey then
        art.iconKey = fx.iconKey
        for _, column in ipairs(art.columns) do
            for _, cell in ipairs(column.cells) do
                cell.item = nil
            end
        end
    end
    local wh = fx.slotHeight - 2 * GATE_CORNER
    local reach = wh / 2 + BANDIT_STRIDE / 2
    for _, column in ipairs(art.columns) do
        -- a reel that hasn't moved since it was last painted is left as it is
        if column.painted ~= column.pos or column.paintedCount ~= count then
            column.painted, column.paintedCount = column.pos, count
            local first = math.floor((column.pos - reach) / BANDIT_STRIDE)
            local blur = column.speed > 300
            for n, cell in ipairs(column.cells) do
                if count > 0 then
                    local k = first + n - 1
                    local y = k * BANDIT_STRIDE - column.pos
                    local index = ((k + column.seed) % count) + 1
                    local entry = icons[index]
                    if fx.claim and column.mode ~= "spin" and k == column.k then
                        -- a reward to choose (Case.OpenClaim): every reel stops on it (the reward
                        -- itself marks the cell, so another reward paints anew)
                        index, entry = fx.claim, fx.claim
                    end
                    if cell.item ~= index then
                        cell.item = index
                        local icon = type(entry) == "table" and entry.icon or entry
                        cell.icon:SetTexture(icon)
                        cell.ghost:SetTexture(icon)
                        local color = TierColor(entry)
                        if color then
                            ColorTexture(cell.back, color[1], color[2], color[3], 1)
                            cell.back:Show()
                        else
                            cell.back:Hide()
                        end
                        cell.icon:Show()
                    end
                    cell.icon:SetPoint("CENTER", column, "CENTER", 0, y)
                    cell.back:SetPoint("CENTER", column, "CENTER", 0, y)
                    if blur then
                        cell.ghost:SetPoint("CENTER", column, "CENTER", 0, y + column.speed * 0.012)
                    end
                    if cell.blurred ~= blur then
                        cell.blurred = blur
                        cell.ghost:SetShown(blur)
                    end
                else
                    cell.item, cell.blurred = nil, false
                    cell.icon:Hide()
                    cell.ghost:Hide()
                    cell.back:Hide()
                end
            end
        end
    end
end

local function Bulbs(fx, art)
    local now = Now()
    local flashing = (fx.flash or 0) > 0
    local key
    if flashing then
        key = math.floor(now * 14) % 2 == 0 and -1 or -2
    else
        key = math.floor(now * 7)
    end
    if art.bulbKey == key then
        return
    end
    art.bulbKey = key
    for _, bulb in ipairs(art.bulbs) do
        local lit
        if flashing then
            lit = key == -1
        else
            lit = (bulb.index + bulb.row + key) % 3 == 0
        end
        if lit and flashing then
            bulb.core:SetVertexColor(1, 0.84, 0.35)
            bulb.halo:SetVertexColor(1, 0.7, 0.1)
            bulb.halo:SetAlpha(0.95)
        elseif lit then
            bulb.core:SetVertexColor(1, 0.95, 0.72)
            bulb.halo:SetVertexColor(1, 0.9, 0.55)
            bulb.halo:SetAlpha(0.85)
        else
            bulb.core:SetVertexColor(0.42, 0.29, 0.12)
            bulb.halo:SetAlpha(0)
        end
    end
end

local function Jackpot(fx)
    fx.flash = 1.4
    local cx = (REEL_LEFT - REEL_RIGHT) / 2
    for _ = 1, 16 do
        local p = Spawn(fx, "coin", cx + Random(-8, 8), 0, Random(-110, 110), Random(95, 200), Random(1.1, 1.5), Random(7, 10))
        if p then
            p.g, p.spin, p.grow, p.late = -430, Random(8, 15), 0, true
        end
    end
end

STYLE.bandit = {
    openFor = 0.42,
    closeFor = 0.62,
    Enter = function(fx)
        local art = BanditArt(fx)
        Levels(fx, false)
        FaceMode(fx, "shutter")
        Doors(fx, fx.slotHeight, 0)
        Seams(fx, nil)
        fx.window:Hide()
        fx.marker:Hide()
        LayoutBandit(fx, art)
        art.frame:SetFrameLevel(fx.level + 1)
        art.frame:Show()
        art.slats:Show()
        art.bulbKey, art.blind, art.gold = nil, nil, nil
        fx.cycle, fx.flash = 0, 0
        for _, column in ipairs(art.columns) do
            column.mode, column.speed, column.painted = "spin", 0, nil
            for _, cell in ipairs(column.cells) do
                cell.blurred = nil
            end
        end
    end,
    Update = function(fx, dt)
        local art = fx.banditArt
        local h = fx.slotHeight
        local blind
        if fx.phase == "opening" then
            blind = EaseInOut(fx.t / 0.42)
        elseif fx.phase == "open" then
            blind = 1
        else
            blind = 1 - EaseOutBounce(fx.t / 0.62)
        end
        -- the shutter: the face rolls up inside the top gate, which covers the slot
        if art.blind ~= blind then
            art.blind = blind
            local face = fx.topDoor.face
            face:SetPoint("TOPLEFT", fx, "TOPLEFT", 0, blind * h)
            face:SetPoint("TOPRIGHT", fx, "TOPRIGHT", 0, blind * h)
            art.slats:SetAlpha((blind > 0.002 and blind < 0.998) and 1 or 0)
            Doors(fx, blind < 0.998 and h or 0, 0)
        end
        -- the reels: all spin, then stop left to right; the middle one landing on an S-tier
        -- item hits the jackpot
        fx.cycle = fx.cycle + dt
        local held = 0
        for c, column in ipairs(art.columns) do
            if column.mode == "spin" then
                column.speed = math.min(900, column.speed + 3600 * dt)
                column.pos = column.pos + column.speed * dt
                if fx.cycle >= 0.65 + (c - 1) * 0.3 then
                    local k = math.ceil(column.pos / BANDIT_STRIDE) + 4
                    column.mode, column.t, column.from, column.k = "stop", 0, column.pos, k
                    column.dist = k * BANDIT_STRIDE - column.pos
                end
            elseif column.mode == "stop" then
                column.t = column.t + dt
                local p = Clamp01(column.t / 0.95)
                column.pos = column.from + column.dist * EaseOutBack(p, 1.25)
                column.speed = p < 1 and column.speed * 0.9 or 0
                if p >= 1 then
                    column.mode = "held"
                    local count = type(fx.icons) == "table" and #fx.icons or 0
                    -- the middle reel's item, unless it stops on a reward (its jackpot comes below)
                    if c == 2 and count > 0 and not fx.claim then
                        local color = TierColor(fx.icons[((column.k + column.seed) % count) + 1])
                        if color == TIER_BACK.S then
                            Jackpot(fx)
                        end
                    end
                end
            else
                held = held + 1
            end
        end
        if fx.claim and held == 3 and not fx.landedAt then
            -- three of the reward: the jackpot, and they stay
            fx.landedAt = Now()
            Jackpot(fx)
        end
        if fx.phase == "open" and held == 3 and not fx.claim and fx.cycle >= 0.65 + 0.6 + 0.95 + 1.3 then
            fx.cycle = 0
            for _, column in ipairs(art.columns) do
                column.mode, column.speed = "spin", 0
            end
        end
        PaintBandit(fx, art)
        fx.flash = math.max(0, fx.flash - dt)
        Bulbs(fx, art)
        local gold = fx.flash > 0
        if art.gold ~= gold then
            art.gold = gold
            ColorTexture(art.payline, 1, gold and 0.84 or 0.29, gold and 0.35 or 0.23, 1)
        end
    end,
    Rest = function(fx)
        local art = fx.banditArt
        if art then
            art.frame:Hide()
            art.slats:Hide()
        end
        fx.flash = 0
        RestCommon(fx)
    end,
}

-- --- Arcane Portal: a rune ring opens a portal from the centre and collapses with a flash -----------------------------

local function ArcaneArt(fx)
    local art = fx.arcaneArt
    if art then
        return art
    end
    art = {}
    local back = fx:CreateTexture(nil, "BACKGROUND")
    back:SetAllPoints(fx)
    back:SetTexture(MEDIA .. "CasePortal")
    back:Hide()
    art.back = back
    local runes = fx.window:CreateTexture(nil, "BORDER")
    runes:SetTexture(MEDIA .. "CaseRunes")
    runes:SetVertexColor(0.71, 0.4, 1)
    runes:SetAlpha(0.35)
    runes:SetSize(96, 96)
    runes:SetPoint("CENTER", fx.window, "CENTER", 1, 0)
    runes:Hide()
    art.runes = runes
    local glow = fx.window:CreateTexture(nil, "BORDER", nil, 1)
    glow:SetTexture(MEDIA .. "CaseGlow")
    glow:SetBlendMode("ADD")
    glow:SetVertexColor(0.7, 0.42, 1)
    glow:SetAlpha(0.85)
    glow:SetSize(76, 76)
    glow:SetPoint("CENTER", fx.window, "CENTER", 1, 0)
    glow:Hide()
    art.glow = glow
    local ring = fx.top:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(MEDIA .. "CaseRing")
    ring:SetBlendMode("ADD")
    ring:SetVertexColor(0.71, 0.4, 1)
    ring:SetPoint("CENTER", fx, "CENTER", 0, 0)
    ring:Hide()
    art.ring = ring
    local edge = fx.top:CreateTexture(nil, "OVERLAY", nil, 1)
    edge:SetTexture(MEDIA .. "CaseRunes")
    edge:SetBlendMode("ADD")
    edge:SetVertexColor(0.85, 0.72, 1)
    edge:SetPoint("CENTER", fx, "CENTER", 0, 0)
    edge:Hide()
    art.edge = edge
    local flash = fx.top:CreateTexture(nil, "OVERLAY", nil, 2)
    flash:SetTexture(MEDIA .. "CaseGlow")
    flash:SetBlendMode("ADD")
    flash:SetVertexColor(1, 0.94, 1)
    flash:SetPoint("CENTER", fx, "CENTER", 0, 0)
    flash:Hide()
    art.flash = flash
    fx.arcaneArt = art
    return art
end

local function Sparkle(fx, x, y, vx, vy, life, size, r, g, b)
    local p = Spawn(fx, "sparkle", x, y, vx, vy, life, size)
    if p then
        p.drag, p.spin, p.grow = 0.95, Random(-5, 5), -0.4
        p.texture:SetVertexColor(r, g, b)
    end
    return p
end

STYLE.arcane = {
    openFor = 0.6,
    closeFor = 0.56,
    Enter = function(fx)
        local art = ArcaneArt(fx)
        Levels(fx, true)
        FaceMode(fx, "wipe")
        DoorsClosed(fx)
        Seams(fx, nil)
        local w, h = fx.slotWidth, fx.slotHeight
        fx.rmax = math.sqrt(w * w + h * h) / 2 + 8
        art.back:Show()
        art.runes:Show()
        art.glow:Show()
        fx.shade:SetAlpha(0)
        CellBacksAlpha(fx, 0.5)
        MaskOn(fx, art.back, art.runes, art.glow)
        MaskCircle(fx, 0, 0, 0)
        MarkerTint(fx, 0.78, 0.55, 1)
        fx.flashAmount = 0
    end,
    Update = function(fx, dt)
        local art = fx.arcaneArt
        local t, flags, rmax = fx.t, fx.flags, fx.rmax
        local radius
        if fx.phase == "opening" then
            radius = rmax * EaseOutBack(t / 0.6, 1.3)
        elseif fx.phase == "open" then
            radius = rmax + 20
        else
            radius = rmax * (1 - EaseInCubic(t / 0.4))
            if t >= 0.4 and not flags.flashed then
                flags.flashed = true
                fx.flashAmount = 1
                for _ = 1, 10 do
                    local a = Random(0, math.pi * 2)
                    Sparkle(fx, 0, 0, math.cos(a) * Random(40, 90), math.sin(a) * Random(40, 90), Random(0.4, 0.7), Random(7, 11), 0.92, 0.82, 1)
                end
            end
        end
        MaskCircle(fx, 0, 0, radius)
        if radius > 0.5 and radius < rmax then
            art.ring:SetSize(2 * radius / 0.965, 2 * radius / 0.965)
            art.ring:Show()
            art.edge:SetSize(2 * (radius + 5) / 0.92, 2 * (radius + 5) / 0.92)
            art.edge:SetRotation(-Now() * 2)
            art.edge:Show()
            if math.random() < dt * 30 then
                local a = Random(0, math.pi * 2)
                Sparkle(fx, math.cos(a) * radius, math.sin(a) * radius, -math.sin(a) * 40, math.cos(a) * 40, Random(0.35, 0.6), Random(5, 8), 0.95, 0.9, 1)
            end
        else
            art.ring:Hide()
            art.edge:Hide()
        end
        if fx.phase == "open" and math.random() < dt * 9 then
            Sparkle(fx, Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -fx.slotHeight / 2 + GATE_CORNER + 4, Random(-6, 6), Random(12, 26), Random(0.8, 1.3), Random(4, 6), 0.81, 0.65, 1)
        end
        art.runes:SetRotation(Now() * 0.5)
        fx.flashAmount = math.max(0, fx.flashAmount - dt * 6)
        if fx.flashAmount > 0 then
            local size = 8 + 68 * (1 - fx.flashAmount)
            art.flash:SetSize(size, size)
            art.flash:SetAlpha(fx.flashAmount)
            art.flash:Show()
        else
            art.flash:Hide()
        end
        local speed = 55
        if fx.phase == "closing" then
            speed = 55 * (1 - Clamp01(t / 0.4))
        end
        MoveReel(fx, speed, dt)
        DressCells(fx, 0, false, false, 2.5, 0)
    end,
    Rest = function(fx)
        local art = fx.arcaneArt
        if art then
            art.back:Hide()
            art.runes:Hide()
            art.glow:Hide()
            art.ring:Hide()
            art.edge:Hide()
            art.flash:Hide()
        end
        RestCommon(fx)
    end,
}

-- --- Frost Shatter: the face freezes, cracks and shatters; ice grows back in and thaws ---------------------------------

local function FrostArt(fx)
    local art = fx.frostArt
    if art then
        return art
    end
    art = { shards = {} }
    local plate = fx.top:CreateTexture(nil, "ARTWORK")
    plate:SetAllPoints(fx)
    plate:SetTexture(MEDIA .. "CaseFrostPlate")
    plate:SetTexCoord(0, 219 / 256, 0, 126 / 128)
    plate:Hide()
    art.plate = plate
    local cracks = fx.top:CreateTexture(nil, "OVERLAY")
    cracks:SetTexture(MEDIA .. "CaseFrostCracks")
    cracks:SetTexCoord(0, 219 / 256, 0, 126 / 128)
    cracks:SetPoint("CENTER", fx, "CENTER", 0, 0)
    cracks:Hide()
    art.cracks = cracks
    local edge = fx.top:CreateTexture(nil, "ARTWORK", nil, 1)
    edge:SetTexture(MEDIA .. "CaseFrostEdge")
    edge:SetTexCoord(0, 219 / 256, 0, 126 / 128)
    edge:SetPoint("CENTER", fx, "CENTER", 0, 0)
    edge:Hide()
    art.edge = edge
    art.vignettes = {}
    for side = 1, 2 do
        local glow = fx.mid:CreateTexture(nil, "OVERLAY")
        glow:SetTexture(MEDIA .. "CaseGlow")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(0.62, 0.88, 1)
        glow:SetAlpha(0.45)
        glow:Hide()
        art.vignettes[side] = glow
    end
    local layer = EnsureParticles(fx).layer
    for index, shard in ipairs(FROST_SHARDS) do
        local texture = layer:CreateTexture(nil, "OVERLAY", nil, -1)
        texture:SetTexture(MEDIA .. "CaseFrostShards")
        texture:SetTexCoord(shard.l, shard.r, shard.t, shard.b)
        texture:SetSize(shard.w, shard.h)
        texture:Hide()
        art.shards[index] = { texture = texture, x = 0, y = 0, vx = 0, vy = 0, rot = 0, spin = 0, age = 1 }
    end
    fx.frostArt = art
    return art
end

local function Shatter(fx, art)
    for index, shard in ipairs(FROST_SHARDS) do
        local s = art.shards[index]
        local length = math.sqrt(shard.dx * shard.dx + shard.dy * shard.dy)
        local dx, dy = 0, 1
        if length > 0.01 then
            dx, dy = shard.dx / length, shard.dy / length
        end
        local speed = Random(60, 150)
        s.x, s.y, s.vx, s.vy = shard.x, shard.y, dx * speed, dy * speed + 70
        s.rot, s.spin, s.age = 0, Random(-6, 6), 0
        s.texture:SetRotation(0)
        s.texture:SetAlpha(1)
        s.texture:SetPoint("CENTER", fx, "CENTER", s.x, s.y)
        s.texture:Show()
    end
    for _ = 1, 8 do
        local a = Random(0, math.pi * 2)
        local p = Dust(fx, 0, 0, math.cos(a) * Random(20, 60), math.sin(a) * Random(15, 40), Random(0.6, 1.0), Random(12, 20), 0.55)
        if p then
            p.texture:SetVertexColor(0.85, 0.94, 1)
        end
    end
    for _ = 1, 10 do
        local a = Random(0, math.pi * 2)
        Sparkle(fx, 0, 0, math.cos(a) * Random(50, 120), math.sin(a) * Random(50, 120), Random(0.4, 0.8), Random(4, 7), 0.9, 0.97, 1)
    end
end

local function FlyShards(fx, art, dt)
    for _, s in ipairs(art.shards) do
        if s.age < 0.75 then
            s.age = s.age + dt
            if s.age >= 0.75 then
                s.texture:Hide()
            else
                s.vy = s.vy - 430 * dt
                s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
                s.rot = s.rot + s.spin * dt
                s.texture:SetPoint("CENTER", fx, "CENTER", s.x, s.y)
                s.texture:SetRotation(s.rot)
                s.texture:SetAlpha(1 - Clamp01((s.age - 0.4) / 0.35))
            end
        end
    end
end

STYLE.frost = {
    openFor = 1.0,
    closeFor = 0.8,
    Enter = function(fx)
        local art = FrostArt(fx)
        Levels(fx, false)
        FaceMode(fx, "wipe")
        DoorsClosed(fx)
        Seams(fx, nil)
        ColorTexture(fx.shade, 0.024, 0.07, 0.11, 1)
        CellBacksAlpha(fx, 0.78)
        MarkerTint(fx, 0.62, 0.88, 1)
        local wh = fx.slotHeight - 2 * GATE_CORNER
        for side, glow in ipairs(art.vignettes) do
            glow:SetSize(52, wh * 1.4)
            glow:SetPoint("CENTER", fx.window, side == 1 and "LEFT" or "RIGHT", 0, 0)
            glow:Show()
        end
        art.plate:SetAlpha(0)
        art.plate:Show()
        art.cracks:Hide()
        art.edge:Hide()
    end,
    Update = function(fx, dt)
        local art = fx.frostArt
        local t, flags = fx.t, fx.flags
        local w, h = fx.slotWidth, fx.slotHeight
        local speed = 0
        if fx.phase == "opening" then
            if t < 0.25 then
                art.plate:SetAlpha(Clamp01(t / 0.22))
                local q = EaseOutCubic((t - 0.05) / 0.2)
                if q > 0 then
                    art.cracks:SetSize(w * (0.4 + 0.6 * q), h * (0.4 + 0.6 * q))
                    art.cracks:SetAlpha(q)
                    art.cracks:Show()
                end
            else
                if not flags.shattered then
                    flags.shattered = true
                    art.plate:Hide()
                    art.cracks:Hide()
                    Doors(fx, 0, 0)
                    Shatter(fx, art)
                end
                speed = 80 * EaseOutCubic((t - 0.25) / 0.6)
            end
        elseif fx.phase == "open" then
            speed = 80
        else
            speed = 80 * (1 - Clamp01(t / 0.45))
            local p = EaseOutCubic(t / 0.45)
            local grow = 1.35 - 0.35 * p
            art.edge:SetSize(w * grow, h * grow)
            art.edge:SetAlpha(p)
            art.edge:Show()
            art.plate:SetAlpha(p * 0.9)
            art.plate:Show()
            if t > 0.45 then
                local q = EaseInOut((t - 0.45) / 0.3)
                if not flags.thawing then
                    flags.thawing = true
                    DoorsClosed(fx)
                end
                fx.topDoor:SetAlpha(q)
                fx.bottomDoor:SetAlpha(q)
                art.plate:SetAlpha(0.9 * (1 - q))
                art.edge:SetAlpha(1 - q)
            end
        end
        FlyShards(fx, art, dt)
        MoveReel(fx, speed, dt)
    end,
    Rest = function(fx)
        local art = fx.frostArt
        if art then
            art.plate:Hide()
            art.cracks:Hide()
            art.edge:Hide()
            for _, glow in ipairs(art.vignettes) do
                glow:Hide()
            end
            for _, s in ipairs(art.shards) do
                s.age = 1
                s.texture:Hide()
            end
        end
        RestCommon(fx)
    end,
}

-- --- Fel Fire: a line of fel fire burns the face away from the bottom, and runs back down to close ----------------------

local function FelArt(fx)
    local art = fx.felArt
    if art then
        return art
    end
    art = {}
    local edge = fx.top:CreateTexture(nil, "OVERLAY")
    edge:SetTexture(MEDIA .. "CaseFelEdge", "REPEAT", "CLAMP")
    edge:Hide()
    art.edge = edge
    local heat = fx.mid:CreateTexture(nil, "OVERLAY")
    heat:SetTexture(MEDIA .. "CaseGlow")
    heat:SetBlendMode("ADD")
    heat:SetVertexColor(0.35, 1, 0.16)
    heat:Hide()
    art.heat = heat
    fx.felArt = art
    return art
end

local function Ember(fx, x, y, vx, vy, g, life)
    local p = Spawn(fx, "ember", x, y, vx, vy, life, Random(3, 5))
    if p then
        p.g, p.grow = g, -0.3
        if math.random() < 0.25 then
            p.texture:SetVertexColor(0.91, 1, 0.6)
        else
            p.texture:SetVertexColor(0.49, 1, 0.23)
        end
    end
end

STYLE.fel = {
    openFor = 0.8,
    closeFor = 0.8,
    Enter = function(fx)
        local art = FelArt(fx)
        Levels(fx, false)
        FaceMode(fx, "wipe")
        Doors(fx, fx.slotHeight, 0)
        Seams(fx, nil)
        ColorTexture(fx.shade, 0.02, 0.04, 0.016, 1)
        CellBacksAlpha(fx, 0.85)
        MarkerTint(fx, 0.55, 1, 0.29)
        art.edge:SetSize(fx.slotWidth + 8, 18)
        art.heat:SetSize(fx.windowWidth * 1.2, 70)
        art.heat:SetPoint("CENTER", fx, "BOTTOM", 0, GATE_CORNER)
        art.heat:Show()
        fx.felScroll = 0
    end,
    Update = function(fx, dt)
        local art = fx.felArt
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local line -- the fire, down from the top of the slot
        if fx.phase == "opening" then
            line = h + 10 - (h + 20) * EaseInOut(t / 0.8)
        elseif fx.phase == "open" then
            line = -10
        else
            line = -10 + (h + 20) * EaseInOut(t / 0.8)
        end
        -- the face above the line: the top gate, cut at it
        Doors(fx, math.max(0, math.min(h, line)), 0)
        if line > -8 and line < h + 8 then
            fx.felScroll = (fx.felScroll + dt * 0.35) % 1
            art.edge:SetPoint("CENTER", fx, "TOP", 0, -line)
            art.edge:SetTexCoord(fx.felScroll, fx.felScroll + (w + 8) / 144, 0, 1)
            art.edge:Show()
            local down = fx.phase == "closing"
            for _ = 1, 2 do
                if math.random() < dt * 14 then
                    Ember(fx, Random(-w / 2 + 2, w / 2 - 2), h / 2 - line, Random(-12, 12), down and Random(-70, -20) or Random(30, 80), down and -60 or 20, Random(0.5, 1.0))
                end
            end
            if down and math.random() < dt * 14 then
                local p = Spawn(fx, "ash", Random(-w / 2 + 2, w / 2 - 2), h / 2 - line + Random(0, 10), Random(-8, 8), Random(-30, -10), Random(0.6, 1.0), 2.4)
                if p then
                    p.spin, p.grow, p.alpha = Random(-3, 3), 0, 0.7
                    p.texture:SetVertexColor(0.17, 0.16, 0.15)
                end
            end
        else
            art.edge:Hide()
        end
        art.heat:SetAlpha(fx.phase == "open" and 0.35 or 0.2)
        if fx.phase == "open" and math.random() < dt * 14 then
            Ember(fx, Random(-fx.windowWidth / 2 + 4, fx.windowWidth / 2 - 4), -h / 2 + GATE_CORNER, Random(-6, 6), Random(20, 45), 0, Random(0.8, 1.4))
        end
        MoveReel(fx, 100, dt)
        DressCells(fx, 0, false, false, 0, fx.phase == "open" and 1.3 or 0.6)
    end,
    Rest = function(fx)
        local art = fx.felArt
        if art then
            art.edge:Hide()
            art.heat:Hide()
        end
        RestCommon(fx)
    end,
}

-- --- Old Cartoon: squash, an iris opens with a pop, the reel zips in; the iris closes on one item ------------------------

local function CartoonArt(fx)
    local art = fx.cartoonArt
    if art then
        return art
    end
    art = {}
    local ring = fx.top:CreateTexture(nil, "OVERLAY")
    ring:SetTexture(MEDIA .. "CaseInkRing")
    ring:Hide()
    art.ring = ring
    local lines = fx.mid:CreateTexture(nil, "OVERLAY")
    lines:SetTexture(MEDIA .. "CaseSpeed", "REPEAT", "CLAMP")
    lines:SetAllPoints(fx.window)
    lines:Hide()
    art.lines = lines
    fx.cartoonArt = art
    return art
end

local function InkPuff(fx, x, y, vx, vy, life, size)
    local p = Spawn(fx, "ink", x, y, vx, vy, life, size)
    if p then
        p.drag, p.grow = 0.9, 0.9
    end
end

STYLE.cartoon = {
    openFor = 0.75,
    closeFor = 0.95,
    Enter = function(fx)
        local art = CartoonArt(fx)
        Levels(fx, true)
        FaceMode(fx, "squash")
        DoorsClosed(fx)
        Seams(fx, nil)
        local w, h = fx.slotWidth, fx.slotHeight
        fx.rmax = math.sqrt(w * w + h * h) / 2 + 8
        MaskOn(fx, art.lines)
        MaskCircle(fx, 0, 0, 0)
        CutGates(fx)
        art.lines:SetAlpha(0)
        art.lines:Show()
        fx.squash, fx.squashSpeed, fx.lineScroll = 0, 0, 0
    end,
    Update = function(fx, dt)
        local art = fx.cartoonArt
        local t, flags, rmax = fx.t, fx.flags, fx.rmax
        local w, h = fx.slotWidth, fx.slotHeight
        local target, speed, radius, cx = 0, 0, 0, 0
        local snapping = false
        if fx.phase == "opening" then
            if t < 0.12 then
                target = -0.1
            else
                if not flags.popped then
                    flags.popped = true
                    for n = 0, 6 do
                        local a = n / 7 * math.pi * 2 + Random(-0.3, 0.3)
                        InkPuff(fx, math.cos(a) * 12, math.sin(a) * 9, math.cos(a) * Random(50, 90), math.sin(a) * Random(35, 60), Random(0.45, 0.7), Random(11, 16))
                    end
                end
                radius = rmax * EaseOutBack((t - 0.12) / 0.5, 1.6)
                local tau = t - 0.12
                speed = 100 + 1500 * math.exp(-tau / 0.22) * math.cos(tau * 10)
            end
        elseif fx.phase == "open" then
            radius = rmax + 30
            local tau = t + 0.63
            speed = 100 + 1500 * math.exp(-tau / 0.22) * math.cos(tau * 10)
        else
            -- the reel settles an item under the marker; the iris closes around it
            snapping = true
            cx = (REEL_LEFT - REEL_RIGHT) / 2
            if fx.entered then
                local marker = fx.windowWidth / 2 + 1
                local distance = ((fx.offset or 0) + CASE_STRIDE / 2 - marker) % CASE_STRIDE
                -- already centred (a hair short of a whole item is rounding), or a reward's reel,
                -- which stops on the reward by itself
                if fx.claim or distance > CASE_STRIDE - 0.01 then
                    distance = 0
                end
                fx.snapDistance = distance
                fx.snapDone = 0
            end
            local goal = (fx.snapDistance or 0) * EaseOutCubic(t / 0.35)
            MoveReelBy(fx, goal - (fx.snapDone or 0))
            fx.snapDone = goal
            if t < 0.35 then
                radius = 22 + (rmax - 22) * (1 - EaseInCubic(t / 0.35))
            elseif t < 0.75 then
                radius = 22 + math.sin((t - 0.35) * 9) * 0.8
            else
                radius = 22 * (1 - EaseInCubic((t - 0.75) / 0.15))
            end
            if t >= 0.9 and not flags.poof then
                flags.poof = true
                InkPuff(fx, cx, 0, 0, 10, 0.45, 14)
            end
        end
        -- squash and stretch: a spring toward `target`, so it overshoots. A stiff spring stepped a
        -- long frame at a time runs away (from about 12 fps), so it's stepped at most 1/60 s at a time.
        local left = dt
        while left > 0 do
            local step = math.min(left, REEL_TICK)
            fx.squashSpeed = fx.squashSpeed + ((target - fx.squash) * 320 - fx.squashSpeed * 14) * step
            fx.squash = fx.squash + fx.squashSpeed * step
            left = left - step
        end
        local fw, fh = w * (1 - fx.squash * 0.5), h * (1 + fx.squash)
        fx.topDoor.face:SetSize(fw, fh)
        fx.bottomDoor.face:SetSize(fw, fh)
        MaskCircle(fx, cx, 0, radius)
        if radius > 0.5 and radius < rmax + 5 then
            local size = 2 * (radius + 1.5) / 0.955
            art.ring:SetSize(size, size)
            art.ring:SetPoint("CENTER", fx, "CENTER", cx, 0)
            art.ring:Show()
        else
            art.ring:Hide()
        end
        if snapping then
            MoveReel(fx, 0, dt)
        else
            MoveReel(fx, speed, dt)
        end
        fx.lineScroll = (fx.lineScroll + speed * dt / 400) % 1
        art.lines:SetTexCoord(fx.lineScroll, fx.lineScroll + fx.windowWidth / 256, 0, 1)
        art.lines:SetAlpha(Clamp01((math.abs(speed) - 350) / 900) * 0.8)
        DressCells(fx, 0.06, false, true, 0, 0)
        fx.markerGlow:SetAlpha(fx.pulse * 0.5)
    end,
    Rest = function(fx)
        local art = fx.cartoonArt
        if art then
            art.ring:Hide()
            art.lines:Hide()
        end
        RestCommon(fx)
    end,
}

-- --- styles from other files ---------------------------------------------------------------------------------

-- Adds a style: `entry` as in Case.STYLES (its specialization opens with it), `style` with
-- openFor, closeFor, Enter, Update and Rest as above.
function Case.AddStyle(entry, style)
    Case.STYLES[#Case.STYLES + 1] = entry
    STYLE[entry.id] = style
    if entry.spec then
        SPEC_STYLE[entry.spec] = entry.id
    end
    if entry.id ~= "classic" then
        RANDOM_POOL[#RANDOM_POOL + 1] = entry.id
    end
end

for _, entry in ipairs(Case.STYLES) do
    if entry.spec then
        SPEC_STYLE[entry.spec] = entry.id
    end
    if entry.id ~= "classic" then
        RANDOM_POOL[#RANDOM_POOL + 1] = entry.id
    end
end

-- What CaseStyles.lua builds its styles from.
Case.kit = {
    MEDIA = MEDIA, GATE_CORNER = GATE_CORNER, CASE_STRIDE = CASE_STRIDE, KINDS = KINDS, STYLE = STYLE,
    Clamp01 = Clamp01, Smooth = Smooth, EaseOutCubic = EaseOutCubic, EaseInCubic = EaseInCubic,
    EaseInOut = EaseInOut, EaseOutBack = EaseOutBack, EaseOutBounce = EaseOutBounce, Random = Random,
    ColorTexture = ColorTexture, FaceAtlas = FaceAtlas, SlotSize = SlotSize, Levels = Levels,
    FaceMode = FaceMode, Doors = Doors, DoorsClosed = DoorsClosed, GateLayout = GateLayout,
    Seams = Seams, Shake = Shake, MarkerTint = MarkerTint, EnsureMarkerGlow = EnsureMarkerGlow,
    MoveReel = MoveReel, EnsureGhosts = EnsureGhosts, DressCells = DressCells,
    CellBacksAlpha = CellBacksAlpha, Spawn = Spawn, MaskOn = MaskOn, MaskCircle = MaskCircle,
    MaskShape = MaskShape, CutGates = CutGates, RestCommon = RestCommon, Shatter = Shatter,
    FlyShards = FlyShards, FaceTint = FaceTint, Now = Now,
}

-- --- the vault's rewards to choose from ---------------------------------------------------------------------

-- The reward's name and item level once it has landed, on a dark plate with a fine border (the
-- popup's look), sized to the text and centred under the reward: it reads over any style's reel or
-- art. In the case, so the gates cover it as they close.
local CLAIM_PAD_X, CLAIM_PAD_Y = 8, 3

local function EnsureClaimLabel(fx)
    local label = fx.claimLabel
    if label then
        return label
    end
    label = CreateFrame("Frame", nil, fx)
    label:EnableMouse(false)
    label:SetPoint("BOTTOM", fx, "BOTTOM", (REEL_LEFT - REEL_RIGHT) / 2, GATE_CORNER + 3)
    label:SetSize(80, CLAIM_BAR)
    label.plate = Utils.Pixel(label, "BACKGROUND", 0.055, 0.055, 0.065, 0.92)
    label.plate:SetAllPoints()
    Utils.Border(label, 0.24, 0.24, 0.27, 1)
    label.name = Utils.FontString(label, "OVERLAY", "Normal")
    label.name:SetPoint("TOP", label, "TOP", 0, -CLAIM_PAD_Y)
    label.name:SetWordWrap(false)
    label.name:SetJustifyH("CENTER")
    label.ilvl = Utils.FontString(label, "OVERLAY", "HighlightSmall")
    label.ilvl:SetPoint("TOP", label.name, "BOTTOM", 0, -1)
    label:Hide()
    fx.claimLabel = label
    return label
end

-- The reward's name, quality and item level, once the game has the item (asked at most four times
-- a second). The item level is the vault's own, from the reward's link.
local function ResolveClaim(claim)
    local now = Now()
    if claim.triedAt and now - claim.triedAt < 0.25 then
        return
    end
    claim.triedAt = now
    local link = C_WeeklyRewards and type(C_WeeklyRewards.GetItemHyperlink) == "function"
        and Utils.Call(C_WeeklyRewards.GetItemHyperlink, claim.itemDBID) or nil
    if not (C_Item and type(C_Item.GetItemInfo) == "function") then
        return
    end
    local name, _, quality = Utils.Call(C_Item.GetItemInfo, link or claim.itemID)
    if type(name) ~= "string" or name == "" then
        return
    end
    claim.name, claim.quality = name, quality
    if link and type(C_Item.GetDetailedItemLevelInfo) == "function" then
        local level = Utils.Call(C_Item.GetDetailedItemLevelInfo, link)
        claim.level = Utils.IsUsableNumber(level) and level or nil
    end
end

local function QualityColor(quality)
    if Utils.IsUsableNumber(quality) and C_Item and type(C_Item.GetItemQualityColor) == "function" then
        local r, g, b = Utils.Call(C_Item.GetItemQualityColor, quality)
        if Utils.IsUsableNumber(r) then
            return r, g, b
        end
    end
    return 1, 0.82, 0
end

-- Each frame of a case holding a reward: once it has landed, the marker fades and the name shows,
-- only while the case is open (some styles draw the gates under the case while they move).
local function ClaimTick(fx)
    local claim = fx.claim
    if not fx.dressed then
        DressCells(fx, 0, false, false, 0, 0)
    end
    local landed = fx.landedAt and Now() - fx.landedAt or -1
    local markerAlpha = landed < 0 and 1 or 1 - Clamp01(landed / 0.25)
    if fx.markerAlpha ~= markerAlpha then
        fx.markerAlpha = markerAlpha
        fx.marker:SetAlpha(markerAlpha)
    end
    local label = EnsureClaimLabel(fx)
    local shown = 0
    if landed >= 0 and fx.phase == "open" then
        shown = math.min(Clamp01((landed - 0.1) / 0.3), Clamp01(fx.t / 0.2))
    end
    if shown <= 0 then
        if label:IsShown() then
            label:Hide()
        end
        return
    end
    if not claim.name then
        ResolveClaim(claim)
    end
    if claim.name and label.shownFor ~= claim then
        label.name:SetText(claim.name)
        label.name:SetTextColor(QualityColor(claim.quality))
        label.ilvl:SetText(claim.level and string.format(L["%d ilvl"], claim.level) or "")
        -- the plate fits the text (at any text size); a long name is cut short to the reel's width
        label.name:SetWidth(0)
        local widest = SLOT_W - REEL_LEFT - REEL_RIGHT - 2 * CLAIM_PAD_X - 8
        local nameWidth = math.min(widest, math.ceil(label.name:GetStringWidth() or 0))
        label.name:SetWidth(nameWidth)
        local width = math.max(nameWidth, math.ceil(label.ilvl:GetStringWidth() or 0)) + 2 * CLAIM_PAD_X
        local height = math.ceil((label.name:GetStringHeight() or 12) + (label.ilvl:GetStringHeight() or 10)) + 1 + 2 * CLAIM_PAD_Y
        label:SetSize(width, height)
        label.shownFor = claim
    end
    -- above the reel and whatever a style puts over it; the gates, beside the case, cover it
    local frameLevel = fx:GetFrameLevel() + 5
    if label.frameLevel ~= frameLevel then
        label:SetFrameLevel(frameLevel)
        label.frameLevel = frameLevel
    end
    if label.shownAlpha ~= shown then
        label.shownAlpha = shown
        label:SetAlpha(shown)
    end
    if label:IsShown() ~= (claim.name ~= nil) then
        label:SetShown(claim.name ~= nil)
    end
end

-- The case lets go of its reward: back to how any case is.
local function ClearClaim(fx)
    if not fx.claim then
        return
    end
    fx.claim, fx.claimHeld, fx.settling, fx.settled = nil, nil, nil, nil
    fx.claimStyle, fx.claimStyleID = nil, nil
    fx.land, fx.landedAt, fx.landItem, fx.landEntry = nil, nil, nil, nil
    fx.reelReady = nil
    fx.marker:SetAlpha(1)
    fx.markerAlpha = nil
    if fx.claimLabel then
        fx.claimLabel:Hide()
        fx.claimLabel.shownFor = nil
    end
end

-- --- the engine: opening, open, closing, and back to rest ---------------------------------------------------------------

-- One OnUpdate drives every animating slot, once per rendered frame, so the animations run at the
-- game's frame rate. It's set only while a slot animates; with none, nothing runs.
local driver = CreateFrame("Frame", nil, UIParent)
local active, activeCount = {}, 0
local Tick, Drive, Failed

-- What the animations cost, for /bgv perf: this run of frames, and the last finished one.
Case.stats = { frames = 0, time = 0, peak = 0, seconds = 0 }
Case.lastStats = nil

local function StartDriving(fx)
    fx.driven = true
    if fx.listed then
        return
    end
    fx.listed = true
    activeCount = activeCount + 1
    active[activeCount] = fx
    if activeCount == 1 then
        local stats = Case.stats
        stats.frames, stats.time, stats.peak, stats.seconds = 0, 0, 0, 0
        driver:SetScript("OnUpdate", Drive)
    end
end

local driving = false

local function Idle()
    driver:SetScript("OnUpdate", nil)
    local stats = Case.stats
    Case.lastStats = { frames = stats.frames, time = stats.time, peak = stats.peak, seconds = stats.seconds }
end

-- A stopped slot leaves the list on the driver's next frame; stopped from outside it (the vault
-- closing, a refresh), the driver stops at once when no slot is left.
local function StopTicker(fx)
    fx.driven = false
    if driving then
        return
    end
    for index = 1, activeCount do
        if active[index].driven then
            return
        end
    end
    for index = 1, activeCount do
        active[index].listed = false
        active[index] = nil
    end
    if activeCount > 0 then
        activeCount = 0
        Idle()
    end
end

function Drive(_, elapsed)
    driving = true
    local clock = debugprofilestop and debugprofilestop()
    local count = activeCount
    for index = 1, count do
        local fx = active[index]
        if fx and fx.driven then
            local ok, err = pcall(Tick, fx, elapsed)
            if not ok then
                Failed(fx, err)
            end
        end
    end
    -- compact the list: keep slots still animating (and any that started during this frame)
    local kept = 0
    for index = 1, activeCount do
        local fx = active[index]
        if fx.driven then
            kept = kept + 1
            active[kept] = fx
        else
            fx.listed = false
        end
    end
    for index = kept + 1, activeCount do
        active[index] = nil
    end
    activeCount = kept
    local stats = Case.stats
    if clock then
        local spent = debugprofilestop() - clock
        stats.time = stats.time + spent
        if spent > stats.peak then
            stats.peak = spent
        end
    end
    stats.frames = stats.frames + 1
    stats.seconds = stats.seconds + (elapsed or 0)
    driving = false
    if activeCount == 0 then
        Idle()
    end
end

local function EnsureTicker(fx)
    StartDriving(fx)
end

function Case.ActiveCount()
    local count = 0
    for index = 1, activeCount do
        if active[index].driven then
            count = count + 1
        end
    end
    return count
end

-- A style's Enter or Rest, protected like its Update (Drive): one that fails is noted, and the
-- slot's common rest runs in its place.
local function CallStyle(fx, name)
    local ok, err = pcall(fx.style[name], fx)
    if not ok then
        Utils.NoteError("slot animation", err)
        RestCommon(fx)
    end
end

-- The common setup for any style: the slot's face on the gates, the reel and marker showing.
local function Prepare(fx)
    local atlas = FaceAtlas(fx.owner)
    for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
        if gate.face.SetAtlas then
            gate.face:SetAtlas(atlas)
        end
        gate:SetAlpha(1)
    end
    SlotSize(fx)
    ClearShake(fx)
    fx.tintR = nil
    fx.window:Show()
    fx.marker:Show()
    ColorMarker(fx)
    ResetCells(fx)
    PlaceReel(fx)
    fx.pulse, fx.hop, fx.markerItem = 0, 0, nil
end

-- The case opens in its style (the reel as it is). A reward's case keeps the style it was revealed
-- with until it lets go of the reward: closed for Collect and open again, it's the same case.
local function StartCase(fx)
    fx.settling, fx.settled, fx.covered = nil, nil, nil
    Prepare(fx)
    if fx.claim and fx.claimStyle then
        fx.style, fx.styleID = fx.claimStyle, fx.claimStyleID
    else
        fx.style, fx.styleID = PickStyle(fx)
        if fx.claim then
            fx.claimStyle, fx.claimStyleID = fx.style, fx.styleID
        end
    end
    fx.phase, fx.t, fx.entered = "opening", 0, true
    fx.flags = {}
    ShowCase(fx, true)
    CallStyle(fx, "Enter")
    EnsureTicker(fx)
    FadeCaption(fx.owner, 0)
end

-- A style that fails puts its slot to rest rather than failing every frame. A reward's case opens
-- again in the Classic style, so the reward still shows.
function Failed(fx, err)
    Utils.NoteError("slot animation", err)
    fx.driven = false
    pcall(Case.Rest, fx.owner)
    if fx.claim and fx.claimStyleID ~= "classic" and STYLE.classic then
        fx.claimStyle, fx.claimStyleID = STYLE.classic, "classic"
        fx.claimHeld, fx.want = true, true
        pcall(StartCase, fx)
    end
end

local function Finish(fx)
    local owner = fx.owner
    if fx.style then
        CallStyle(fx, "Rest")
    end
    fx.phase, fx.t = "closed", 0
    fx.marker:Hide()
    if fx.claim then
        if fx.claimHeld then
            -- Collect left before the gates had shut: open onto the reward again
            StartCase(fx)
            return
        end
        -- Collect pointed at: the gates stay shut over the reward, for the sad gates (Faces.lua)
        ShowCase(fx, true)
    else
        ShowCase(fx, false)
        FadeCaption(owner, 1)
        if fx.want and VaultIsOpen() and PointerOnSlot(owner) then
            -- pointed at again while it closed
            Case.Open(owner)
            return
        end
    end
    -- effects still in the air finish on their own
    if fx.parts and fx.parts.live > 0 then
        fx.phase = "tail"
    else
        StopTicker(fx)
    end
end

function Tick(fx, elapsed)
    local owner = fx.owner
    local dt = elapsed or REEL_TICK
    if dt > 0.1 then
        dt = 0.1
    elseif dt < 0 then
        dt = 0
    end
    -- The settings' preview plays without the vault, and opens and closes on its own clock.
    if not fx.preview and not VaultIsOpen() then
        Case.Shut(owner)
        return
    end
    if fx.phase == "tail" then
        UpdateParticles(fx, dt)
        if not fx.parts or fx.parts.live == 0 then
            fx.phase = "closed"
            StopTicker(fx)
        end
        return
    end
    if fx.phase == "closed" then
        StopTicker(fx)
        return
    end
    if fx.want and not fx.preview and not fx.claimHeld and not PointerOnSlot(owner) then
        fx.want = false
    end
    local style = fx.style
    fx.t = fx.t + dt
    fx.entered = false
    if fx.phase == "opening" then
        if not fx.want and style.reversible then
            fx.phase, fx.t, fx.entered = "closing", style.closeFor * (1 - Clamp01(fx.t / style.openFor)), true
        elseif fx.t >= style.openFor then
            fx.phase, fx.t, fx.entered = "open", fx.t - style.openFor, true
        end
    elseif fx.phase == "open" then
        if not fx.want then
            fx.phase, fx.t, fx.entered = "closing", 0, true
        end
    elseif fx.phase == "closing" then
        if fx.want and style.reversible then
            fx.phase, fx.t, fx.entered = "opening", style.openFor * (1 - Clamp01(fx.t / style.closeFor)), true
        elseif fx.t >= style.closeFor then
            Finish(fx)
            return
        end
    end
    if fx.settling then
        -- a reward's case settling: the style is still, what's in the air fades, then no more work
        UpdateParticles(fx, dt)
        if not (fx.parts and fx.parts.live > 0) then
            fx.settling, fx.settled = nil, true
            StopTicker(fx)
        end
        return
    end
    RefreshIcons(fx, dt)
    fx.dressed = false
    style.Update(fx, dt)
    if fx.claim then
        ClaimTick(fx)
        local since = fx.landedAt and Now() - fx.landedAt
        if fx.claimHeld and fx.phase == "open" and not fx.land and fx.t > CLAIM_SETTLE and since and since > CLAIM_SETTLE
            and (fx.claim.name or since > CLAIM_NAME_WAIT) then
            fx.settling = true
        end
    end
    UpdateParticles(fx, dt)
    local text = owner.bgvText
    if text and fx.phase ~= "closing" and text.bgvFadeTarget ~= 0 then
        FadeCaption(owner, 0)
    end
end

-- --- what UI.lua calls ------------------------------------------------------------------------------------------

-- Opens the slot's case in its style (if it's not already opening or open).
function Case.Open(activityFrame)
    if AnimationsDisabled() or not activityFrame or not activityFrame.IsShown or not activityFrame:IsShown() then
        return
    end
    local fx = EnsureFX(activityFrame)
    fx.want = true
    local icons = fx.icons
    if type(icons) == "table" and #icons > 0 and not fx.reelReady then
        fx.cursor = math.random(#icons)
        fx.offset = 0
        PaintReel(fx)
        PlaceReel(fx)
        fx.reelReady = true
    end
    if fx.phase ~= "closed" and fx.phase ~= "tail" then
        return
    end
    StartCase(fx)
end

-- Asks the case to close; the ticker closes it once it has finished opening.
function Case.Close(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if fx then
        fx.want = false
    end
end

function Case.IsAnimating(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    return fx ~= nil and fx.phase ~= "closed" and fx.phase ~= "tail"
end

-- The slot at rest: its gates shut over the face, nothing running.
function Case.Rest(activityFrame)
    local fx = EnsureFX(activityFrame)
    fx.covered = nil
    StopTicker(fx)
    if fx.style then
        CallStyle(fx, "Rest")
    else
        RestCommon(fx)
    end
    ClearParticles(fx)
    fx.phase, fx.t, fx.want = "closed", 0, false
    local atlas = FaceAtlas(activityFrame)
    for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
        if gate.face.SetAtlas then
            gate.face:SetAtlas(atlas)
        end
    end
    RaiseAboveGlow(activityFrame)
    Levels(fx, false)
    DoorsClosed(fx)
    ShowCase(fx, false)
    fx.marker:Hide()
    FadeCaption(activityFrame, 1)
end

-- The slot without the case: gates, reel and effects gone (a locked slot, or the vault back to
-- Blizzard's).
function Case.Stop(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    ClearClaim(fx)
    fx.covered = nil
    StopTicker(fx)
    if fx.style then
        CallStyle(fx, "Rest")
    end
    ClearParticles(fx)
    fx.phase, fx.t, fx.want = "closed", 0, false
    ShowCase(fx, false)
    fx.marker:Hide()
    Seams(fx, nil)
    Doors(fx, 0, 0)
    FadeCaption(activityFrame, 1)
end

-- The vault closed with the case open or opening: shut at once, the gates closed over the face
-- of an unlocked slot.
function Case.Shut(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not fx then
        return
    end
    local wasOpen = fx.phase ~= "closed" and fx.phase ~= "tail"
    ClearClaim(fx)
    fx.covered = nil
    StopTicker(fx)
    if fx.style then
        CallStyle(fx, "Rest")
    end
    ClearParticles(fx)
    fx.phase, fx.t, fx.want = "closed", 0, false
    fx.marker:Hide()
    Seams(fx, nil)
    if wasOpen and activityFrame.bgvSlot and activityFrame.bgvSlot.unlocked then
        DoorsClosed(fx)
    end
    ShowCase(fx, false)
    local text = activityFrame.bgvText
    if text then
        if text.bgvFade then
            text.bgvFade:Stop()
        end
        text.bgvFadeTarget = 1
        text:SetAlpha(1)
    end
end

-- --- the vault's rewards to choose from (UI.lua) ------------------------------------------------------------

-- Opens the slot's case onto `reward` ({ itemDBID, itemID, icon }) and holds it open, the reel
-- spinning through `icons` first. The same reward again changes nothing (the case may be shut for
-- the sad gates).
function Case.OpenClaim(activityFrame, reward, icons)
    if AnimationsDisabled() or not activityFrame or not activityFrame.IsShown or not activityFrame:IsShown()
        or type(reward) ~= "table" or type(icons) ~= "table" or #icons == 0 then
        return
    end
    local fx = EnsureFX(activityFrame)
    if fx.claim and fx.claim.itemDBID == reward.itemDBID then
        return
    end
    if fx.claim then
        ClearClaim(fx)
    end
    fx.claim, fx.claimHeld, fx.want = reward, true, true
    fx.icons, fx.iconKey, fx.iconCount, fx.iconsPending = icons, icons, #icons, false
    fx.cursor, fx.offset, fx.reelReady = math.random(#icons), 0, true
    PaintReel(fx)
    PlaceReel(fx)
    if fx.phase == "closed" or fx.phase == "tail" then
        StartCase(fx)
    else
        -- open, perhaps settled (its ticker stopped): it spins again and lands on the new reward
        EnsureTicker(fx)
    end
end

-- A slot whose reward hasn't loaded yet: its gates shut over it, still, so nothing shows before
-- every reward opens together.
function Case.Cover(activityFrame)
    if AnimationsDisabled() or not activityFrame then
        return
    end
    local fx = EnsureFX(activityFrame)
    if fx.phase ~= "closed" or fx.claim then
        return
    end
    RaiseAboveGlow(activityFrame)
    Prepare(fx)
    Levels(fx, false)
    DoorsClosed(fx)
    fx.marker:Hide()
    ShowCase(fx, true)
    fx.covered = true
end

-- Whether the slot is shut waiting for its reward (Case.Cover).
function Case.IsCovered(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    return fx ~= nil and fx.covered == true
end

-- A reward's reel gets a fuller list (it was still loading): swapped in while it still spins.
function Case.SetClaimIcons(activityFrame, icons)
    local fx = activityFrame and activityFrame.bgvFX
    if not (fx and fx.claim) or fx.land or fx.landedAt or type(icons) ~= "table" or #icons == 0 then
        return false
    end
    fx.icons, fx.iconKey, fx.iconCount = icons, icons, #icons
    PaintReel(fx)
    return true
end

-- Collect pointed at: the case closes over its reward, and stays shut until ResumeClaim.
function Case.SuspendClaim(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if fx and fx.claim then
        fx.claimHeld, fx.want = false, false
        if fx.phase ~= "closed" and fx.phase ~= "tail" then
            -- a settled case: awake again, to close
            fx.settling, fx.settled = nil, nil
            EnsureTicker(fx)
        end
    end
end

-- Collect left: open onto the reward again (right away, or once it has finished closing).
function Case.ResumeClaim(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    if not (fx and fx.claim) or AnimationsDisabled() then
        return
    end
    fx.claimHeld, fx.want = true, true
    if fx.phase == "closed" or fx.phase == "tail" then
        StartCase(fx)
    end
end

function Case.HasClaim(activityFrame)
    local fx = activityFrame and activityFrame.bgvFX
    return fx ~= nil and fx.claim ~= nil
end

-- Away from the vault once the rewards are rolled (UI.lua), each slot holding a reward shows it as
-- the reveal leaves it, at once and still. Every case in `list` ({ frame, reward, icons }) opens
-- onto its reward (Case.OpenClaim) and is played to its end in one go, on the animations' clock run
-- ahead, so it ends just as it would have. A reward whose name the game hasn't loaded yet carries on
-- in real time from there, as at the vault, until it has. A case already holding its reward stays.
-- Nothing it would throw into the air is made: it would be gone before it was seen.
local PLAY_STEP, PLAY_LIMIT = 0.1, 15

function Case.ShowClaims(list)
    local playing = {}
    for _, entry in ipairs(list) do
        local fx = entry.frame.bgvFX
        if not (fx and fx.claim and fx.claim.itemDBID == entry.reward.itemDBID) then
            Case.OpenClaim(entry.frame, entry.reward, entry.icons)
            fx = entry.frame.bgvFX
            if fx and fx.claim == entry.reward and fx.driven then
                fx.playingOut = true
                playing[#playing + 1] = fx
            end
        end
    end
    local played = 0
    while #playing > 0 and played < PLAY_LIMIT do
        clockAhead = clockAhead + PLAY_STEP
        played = played + PLAY_STEP
        for index = #playing, 1, -1 do
            local fx = playing[index]
            local ok, err = pcall(Tick, fx, PLAY_STEP)
            if not ok then
                Failed(fx, err)
            end
            -- done: settled (the ticker stopped), or landed and waiting for the reward's name
            local waiting = fx.claim and not fx.claim.name and fx.landedAt and Now() - fx.landedAt > CLAIM_SETTLE
            if not fx.driven or waiting then
                fx.playingOut = nil
                table.remove(playing, index)
            end
        end
    end
    for _, fx in ipairs(playing) do
        fx.playingOut = nil
    end
end

-- --- the settings' preview -----------------------------------------------------------------------------------

-- Pointing at an opening style in the settings' menu plays it beside the menu, on a stand-in slot
-- whose reel holds empty gear slots in place of items: it opens, spins a moment, closes and
-- starts again (Random picks another style each time). It runs only while shown.
local PREVIEW_ICONS = {
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Head",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Shoulder",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Chest",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Hands",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Waist",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Legs",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Feet",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Wrists",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Neck",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Finger",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-Trinket",
    "Interface\\PaperDoll\\UI-PaperDoll-Slot-MainHand",
}
-- Seconds the preview stays open, and closed before it opens again.
local PREVIEW_OPEN, PREVIEW_PAUSE = 1.8, 0.6
local PREVIEW_PAD = 10
local preview

local function PreviewOpen(panel)
    Case.Open(panel.slot)
    local fx = panel.fx
    if fx.styleID then
        panel.title:SetText(Case.StyleName(fx.styleID))
    end
    panel.wait, panel.phase = 0, fx.phase
end

local function PreviewTick(panel, elapsed)
    -- The menu closed (its entry no longer shows): the preview goes with it.
    if not (panel.anchor and panel.anchor:IsVisible()) then
        Case.HidePreview()
        return
    end
    local fx = panel.fx
    if fx.phase ~= panel.phase then
        panel.wait, panel.phase = 0, fx.phase
    end
    panel.wait = panel.wait + (elapsed or 0)
    if fx.phase == "open" and panel.wait >= PREVIEW_OPEN then
        fx.want = false
    elseif (fx.phase == "closed" or fx.phase == "tail") and panel.wait >= PREVIEW_PAUSE then
        PreviewOpen(panel)
    end
end

local function PreviewPanel()
    if preview then
        return preview
    end
    local panel = CreateFrame("Frame", nil, UIParent)
    panel:SetFrameStrata("TOOLTIP")
    if panel.SetClampedToScreen then
        panel:SetClampedToScreen(true)
    end
    panel:EnableMouse(false)
    local body = Utils.Pixel(panel, "BACKGROUND", 0.055, 0.055, 0.065, 0.97)
    body:SetAllPoints()
    Utils.Border(panel, 0.24, 0.24, 0.27, 1)
    local title = Utils.FontString(panel, "OVERLAY", "Normal")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", PREVIEW_PAD, -PREVIEW_PAD)
    title:SetJustifyH("LEFT")
    local slot = CreateFrame("Frame", nil, panel)
    slot:SetSize(SLOT_W, SLOT_H)
    slot:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", PREVIEW_PAD, PREVIEW_PAD)
    local fx = EnsureFX(slot)
    fx.preview = true
    fx.icons, fx.iconKey, fx.iconCount = PREVIEW_ICONS, PREVIEW_ICONS, #PREVIEW_ICONS
    panel.title, panel.slot, panel.fx = title, slot, fx
    panel:Hide()
    panel:SetScript("OnUpdate", PreviewTick)
    preview = panel
    return panel
end

-- Plays `choice` (a style's id, Case.SPEC or Case.RANDOM) beside `anchor`, the menu entry being
-- pointed at: to the right of the menu when the screen has room, else to its left.
function Case.ShowPreview(anchor, choice)
    if not anchor or AnimationsDisabled() then
        return
    end
    local panel = PreviewPanel()
    Case.Rest(panel.slot)
    panel.fx.previewChoice = choice
    panel.anchor = anchor
    local width = SLOT_W + 2 * PREVIEW_PAD
    panel:SetSize(width, SLOT_H + 3 * PREVIEW_PAD + 14)
    panel:ClearAllPoints()
    -- Room right of the entry, in screen pixels (each frame's coordinates times its scale).
    local right, screen = anchor:GetRight(), UIParent:GetRight()
    local room = 0
    if right and screen then
        room = screen * (UIParent:GetEffectiveScale() or 1) - right * (anchor:GetEffectiveScale() or 1)
    end
    if room >= (width + 20) * (panel:GetEffectiveScale() or 1) then
        panel:SetPoint("LEFT", anchor, "RIGHT", 16, 0)
    else
        panel:SetPoint("RIGHT", anchor, "LEFT", -16, 0)
    end
    panel:Show()
    PreviewOpen(panel)
end

function Case.HidePreview()
    if not preview then
        return
    end
    preview.anchor = nil
    preview.fx.previewChoice = nil
    Case.Rest(preview.slot)
    preview:Hide()
end
