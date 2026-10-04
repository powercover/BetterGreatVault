local _, BGV = ...

-- Sad gates: pointing at the vault's Collect reward (a currency offered in place of an item) gives
-- the completed slots' gates a disappointed face, and the slot holding the best reward takes it
-- hardest. Moving away cheers them up for a moment before they go back to normal. In the progress
-- week the faces form on the addon's closed gates; in the claim week the gates close over the
-- rewards while Collect is pointed at. The faces are plain line icons in the vault's ivory with a
-- soft shadow (make_face_media.py). Nothing runs until Collect is pointed at.
BGV.Faces = {}

local Faces = BGV.Faces
local Case = BGV.Case
local Utils = BGV.Utils
local K = Case.kit

local MEDIA = K.MEDIA
local Clamp01, EaseOutCubic, EaseOutBack, EaseInOut = K.Clamp01, K.EaseOutCubic, K.EaseOutBack, K.EaseInOut
local Random = K.Random
local sin, max, min, pi, sqrt, floor = math.sin, math.max, math.min, math.pi, math.sqrt, math.floor

-- Where the features sit, from the slot's centre (up is +y), before the face's scale. Every line
-- has the same weight: the textures' boxes are sized for it.
local SCALE = 1.3
local EYE_X, EYE_Y = 26, 10
local BROW_Y = EYE_Y + 12
local MOUTH_Y = -14
local TEARS = 4
local INK = { 1, 0.94, 0.82 } -- the features: the vault's ivory
local TEAR = { 0.74, 0.88, 1 }

-- The eyes: open (a dot), half-lidded, shut in sorrow (an arc bowed down) or content (bowed up).
local EYES = {
    open = { file = "CaseFaceDot", size = 14 },
    lid = { file = "CaseFaceLid", size = 14 },
    shut = { file = "CaseFaceArc", size = 21, flip = true },
    content = { file = "CaseFaceArc", size = 21 },
}

-- How each face looks and behaves, from the best reward's down. brow: how far the brows' inner ends
-- rise (negative: they drop, a sulk); mouth: how deep the frown (1: deepest); tears: "both" (from
-- each eye in turn), "one" (from one eye) or "held" (one that stays under the eye), every
-- `tearEvery` seconds; sob/sigh: seconds between them; look: where the eyes look.
local MOODS = {
    wail = { eyes = "shut", lidTilt = 0.2, brow = 0.42, browLift = 1.5, mouth = 1, width = 32, tears = "both", tearEvery = 0.55, sob = 1.2, sobDepth = 1.2 },
    cry = { eyes = "open", brow = 0.32, browLift = 1, mouth = 0.85, width = 30, tears = "one", tearEvery = 1.1 },
    plead = { eyes = "open", size = 1.15, brow = 0.5, browLift = 3, mouth = 0.4, width = 26, tears = "held", look = "up" },
    sad = { eyes = "lid", lidTilt = 0.2, brow = 0.22, mouth = 0.7, width = 30, tears = "one", tearEvery = 3.4, sigh = 2.8 },
    sulk = { eyes = "lid", lidTilt = -0.06, squash = 0.85, brow = -0.2, browLift = -1.5, mouth = 0.1, width = 24, side = 6, look = "button" },
}
-- Below the one taking it hardest, the faces in order of how much they lose; the last one sulks.
local MIDDLE = { "cry", "plead", "sad" }

local faces = {} -- the faces on screen
-- Slots still opening or closing when Collect was pointed at: their face (the mood each will show)
-- comes once their gates are shut, if Collect is still pointed at.
local waiting = {}
local pointedAt, pointedClaim -- the Collect button pointed at (nil: none), and whether it's the claim week
local driver

-- --- helpers -----------------------------------------------------------------------------------------------

local function Enabled()
    return not Utils.AnimationsOff() and not (BetterGreatVaultDB and BetterGreatVaultDB.disableCollectFaces == true)
end

local ProgressWeek = Utils.ProgressWeek

local function Show(texture)
    if not texture.bgvOn then
        texture:Show()
        texture.bgvOn = true
    end
end

local function Off(texture)
    if texture.bgvOn then
        texture:Hide()
        texture.bgvOn = false
    end
end

-- Places a feature (x, y) from the slot's centre, `w` by `h`, at the face's scale; only what
-- changed is passed on.
local function Put(face, texture, x, y, w, h, alpha)
    if alpha <= 0.01 or w <= 0.1 or h <= 0.1 then
        Off(texture)
        return
    end
    x, y, w, h = x * SCALE, y * SCALE, w * SCALE, h * SCALE
    if texture.bgvX ~= x or texture.bgvY ~= y then
        texture:SetPoint("CENTER", face.fx, "CENTER", x, y)
        texture.bgvX, texture.bgvY = x, y
    end
    if texture.bgvW ~= w or texture.bgvH ~= h then
        texture:SetSize(w, h)
        texture.bgvW, texture.bgvH = w, h
    end
    if texture.bgvA ~= alpha then
        texture:SetAlpha(alpha)
        texture.bgvA = alpha
    end
    Show(texture)
end

local function Turn(texture, angle)
    if texture.bgvR ~= angle then
        texture:SetRotation(angle)
        texture.bgvR = angle
    end
end

local function NewTexture(face, file, color, layer)
    local texture = face.layer:CreateTexture(nil, layer or "ARTWORK")
    if file then
        texture:SetTexture(MEDIA .. file)
    end
    texture:SetVertexColor(color[1], color[2], color[3])
    texture:Hide()
    face.all[#face.all + 1] = texture
    return texture
end

-- --- a face's parts ----------------------------------------------------------------------------------------

local function Build(activityFrame, fx)
    local layer = CreateFrame("Frame", nil, activityFrame)
    layer:SetAllPoints(fx)
    layer:EnableMouse(false)
    if layer.SetClipsChildren then
        layer:SetClipsChildren(true)
    end
    layer:Hide()
    local face = { owner = activityFrame, fx = fx, layer = layer, all = {}, eyes = {}, brows = {}, tears = {} }
    for side = 1, 2 do
        face.eyes[side] = { texture = NewTexture(face, nil, INK) }
        face.brows[side] = NewTexture(face, "CaseFaceBrow", INK)
    end
    face.mouth = NewTexture(face, "CaseFaceMouth", INK)
    for index = 1, TEARS do
        face.tears[index] = { texture = NewTexture(face, "CaseFaceTear", TEAR, "OVERLAY"), live = false }
    end
    activityFrame.bgvFace = face
    return face
end

-- A tear from under an eye (side 1: left), falling unless it's held there.
local function Weep(face, side, held)
    for _, tear in ipairs(face.tears) do
        if not tear.live then
            local dir = side == 1 and -1 or 1
            tear.live, tear.held, tear.age, tear.vy = true, held, 0, 0
            tear.x, tear.y = dir * (EYE_X + 3), EYE_Y - 9
            return tear
        end
    end
end

-- The tears: each swells under its eye, then falls and fades before the slot's edge.
local function Tears(face, dt)
    local bottom = -face.fx.slotHeight / 2 / SCALE + 6
    local alpha = face.show * (1 - face.relief)
    for _, tear in ipairs(face.tears) do
        if tear.live then
            tear.age = tear.age + dt
            local size = 9 * EaseOutCubic(min(1, tear.age / 0.35))
            if not tear.held and tear.age > 0.35 then
                tear.vy = tear.vy - 180 * dt
                tear.y = tear.y + tear.vy * dt
            end
            local fade = Clamp01((tear.y - bottom) / 14)
            if fade <= 0 or alpha <= 0.01 then
                tear.live = false
                Off(tear.texture)
            else
                Put(face, tear.texture, tear.x, tear.y, size, size, alpha * fade)
            end
        end
    end
end

-- --- how a face moves ---------------------------------------------------------------------------------------

-- A short dip every `every` seconds: a quiet sob.
local function Sob(t, every)
    local phase = t % every
    if phase < 0.25 then
        return sin(pi * phase / 0.25)
    end
    return 0
end

local function Pose(face, dt)
    local mood, show, relief, t = face.mood, face.show, face.relief, face.t
    local feeling = face.sad * (1 - relief)
    local content = relief > 0.5
    -- the blink: now and then open eyes close for a moment
    local open = 1
    if not content and mood.eyes ~= "shut" then
        face.blinkIn = face.blinkIn - dt
        if face.blinkIn <= 0 then
            face.blinkIn = Random(2.5, 5)
            face.blinkAt = t
        end
        local since = t - (face.blinkAt or -1)
        if since >= 0 and since < 0.14 then
            open = 1 - 0.88 * sin(pi * since / 0.14)
        end
    end
    for side = 1, 2 do
        local dir = side == 1 and -1 or 1
        local eye = face.eyes[side]
        local kind = content and "content" or mood.eyes
        local look = EYES[kind]
        if eye.kind ~= kind then
            eye.texture:SetTexture(MEDIA .. look.file)
            if look.flip then
                eye.texture:SetTexCoord(0, 1, 1, 0)
            else
                eye.texture:SetTexCoord(0, 1, 0, 1)
            end
            eye.kind = kind
        end
        local x, y = dir * EYE_X, EYE_Y
        local w, h = look.size, look.size
        if kind == "open" or kind == "lid" then
            local size = 1 + ((mood.size or 1) - 1) * feeling
            w, h = w * size, h * size * (1 - (1 - (mood.squash or 1)) * feeling) * open
            x, y = x + face.lookX * feeling, y + face.lookY * feeling
        end
        -- lids and shut eyes droop at their outer corners in sorrow (a sulk's sit flat)
        local tilt = 0
        if kind == "lid" or kind == "shut" then
            tilt = -dir * (mood.lidTilt or 0) * feeling
        end
        Turn(eye.texture, tilt)
        Put(face, eye.texture, x, y, w, h, show)
        -- the brows: their inner ends raised in sorrow (lowered in a sulk), relaxed when content
        local brow = face.brows[side]
        Turn(brow, -dir * mood.brow * feeling)
        Put(face, brow, dir * (EYE_X + 1), BROW_Y + (mood.browLift or 0) * feeling + 1.5 * relief, 20, 20, show)
    end
    -- the mouth: one of eight curves from a smile to a frown, the line the same in all
    local curve = Clamp01(((mood.mouth or 0.6) * feeling - 0.8 * relief + 1) / 2)
    local cell = floor(curve * 7 + 0.5)
    if face.mouthCell ~= cell then
        face.mouth:SetTexCoord(cell / 8, (cell + 1) / 8, 0, 1)
        face.mouthCell = cell
    end
    local width = mood.width + (32 - mood.width) * relief
    Put(face, face.mouth, (mood.side or 0) * feeling, MOUTH_Y, width, width / 2, show)
    return mood.sob and Sob(t, mood.sob) * feeling or 0
end

-- What a face does while it's held: its tears.
local function Act(face)
    local mood = face.mood
    if not face.entering or face.sad < 0.6 or not mood.tears then
        return
    end
    if mood.tears == "held" then
        if not face.held then
            face.held = true
            Weep(face, 2, true)
        end
    elseif face.t >= face.nextTear then
        face.nextTear = face.t + mood.tearEvery * Random(0.85, 1.15)
        local side
        if mood.tears == "both" then
            side = face.tearSide == 1 and 2 or 1
        else
            side = face.tearSide or (math.random() < 0.5 and 1 or 2)
        end
        face.tearSide = side
        Weep(face, side, false)
    end
end

-- The slot sags a little with the mood, and dips with each sob and sigh.
local function Body(face, sob)
    local mood = face.mood
    local feeling = face.sad * (1 - face.relief)
    local y = -1.5 * feeling - (mood.sobDepth or 0) * sob
    if mood.sigh then
        local phase = face.t % mood.sigh
        if phase < 1 then
            y = y - 2 * feeling * sin(pi * EaseInOut(phase))
        end
    end
    y = floor(y * 4 + 0.5) / 4
    if face.bodyY ~= y then
        local fx = face.fx
        fx:ClearAllPoints()
        fx:SetPoint("TOPLEFT", face.owner, "TOPLEFT", 0, y)
        fx:SetPoint("BOTTOMRIGHT", face.owner, "BOTTOMRIGHT", 0, y)
        face.bodyY = y
    end
end

-- --- a face's life -------------------------------------------------------------------------------------------

local function Finish(face, stopping)
    for _, texture in ipairs(face.all) do
        Off(texture)
    end
    for _, tear in ipairs(face.tears) do
        tear.live = false
    end
    face.layer:Hide()
    face.active = false
    local owner, fx = face.owner, face.fx
    fx:ClearAllPoints()
    fx:SetPoint("TOPLEFT", owner, "TOPLEFT", 0, 0)
    fx:SetPoint("BOTTOMRIGHT", owner, "BOTTOMRIGHT", 0, 0)
    face.bodyY = nil
    if Case.IsAnimating(owner) then
        -- the slot opened meanwhile: its case has the gates and the caption now
        return
    end
    if face.handBack then
        -- a reward's case opens onto it again (the vault closing shuts it instead); one still
        -- waiting for its reward stays shut over it
        if not stopping and Case.HasClaim(owner) then
            Case.ResumeClaim(owner)
        end
    elseif face.claim then
        -- back to Blizzard's slot, exactly as it was
        Case.Stop(owner)
        if owner.bgvBaseLevel then
            owner:SetFrameLevel(owner.bgvBaseLevel)
        end
    else
        Case.FadeCaption(owner, 1)
    end
end

local function Update(face, dt)
    local fx = face.fx
    if Case.IsAnimating(face.owner) then
        Finish(face)
        return false
    end
    face.t = face.t + dt
    if face.entering then
        if face.claim then
            face.gate = min(1, face.gate + dt / 0.22)
        end
        if not face.claim or face.gate > 0.6 then
            face.show = min(1, face.show + dt / 0.2)
            face.sad = min(1, face.sad + dt / 0.4)
        end
        face.relief = max(0, face.relief - dt / 0.2)
    else
        -- relieved: a smile for a moment, then the face fades away (and the gates open, claim week)
        face.left = face.left + dt
        face.sad = max(0, face.sad - dt / 0.2)
        if face.shown then
            face.relief = min(1, face.relief + dt / 0.15)
        end
        if face.left > 0.35 then
            face.show = max(0, face.show - dt / 0.22)
        end
        if face.claim and face.show <= 0 and not face.handBack then
            face.gate = max(0, face.gate - dt / 0.22)
        end
        if face.show <= 0 and (not face.claim or face.handBack or face.gate <= 0) then
            Finish(face)
            return false
        end
    end
    if face.show >= 1 then
        face.shown = true
    end
    local text = face.owner.bgvText
    if face.entering and not face.claim and text and text.bgvFadeTarget ~= 0 then
        Case.FadeCaption(face.owner, 0)
    end
    if face.claim then
        local cover = fx.slotHeight / 2 * EaseOutBack(face.gate, 1.2)
        K.Doors(fx, cover, cover)
    end
    local sob = Pose(face, dt)
    Act(face)
    Tears(face, dt)
    Body(face, sob)
    return true
end

local Begin

local function Drive(_, elapsed)
    local dt = min(elapsed or 0, 0.1)
    -- the slots that were still busy: a face for each as soon as its gates are shut
    local waits = false
    if pointedAt then
        for activityFrame, moodName in pairs(waiting) do
            if not activityFrame:IsShown() then
                waiting[activityFrame] = nil
            elseif Case.IsAnimating(activityFrame) then
                waits = true
            else
                waiting[activityFrame] = nil
                local ok, err = pcall(Begin, activityFrame, moodName, pointedClaim, pointedAt)
                if not ok then
                    Utils.NoteError("sad gates", err)
                end
            end
        end
    end
    local any = false
    for index = #faces, 1, -1 do
        local face = faces[index]
        local ok, alive = true, false
        if face.active then
            ok, alive = pcall(Update, face, dt)
        end
        if ok and alive then
            any = true
        else
            if not ok then
                -- a face that fails goes, rather than failing every frame
                Utils.NoteError("sad gates", alive)
                pcall(Finish, face)
            end
            table.remove(faces, index)
        end
    end
    if not any and not waits then
        driver:SetScript("OnUpdate", nil)
    end
end

-- How good the slot's reward is: in the claim week the item itself (its Best-in-Slot tier for the
-- loot spec, then its item level); in the progress week the item level it will award.
local TIER_RANK = { S = 5, A = 4, B = 3, C = 2, D = 1 }

local function Worth(activityFrame, claim)
    if not claim then
        local slot = activityFrame.bgvSlot
        return slot and Utils.IsUsableNumber(slot.itemLevel) and slot.itemLevel or 0
    end
    local info = activityFrame.info
    local best = 0
    local itemType = Enum and Enum.CachedRewardType and Enum.CachedRewardType.Item
    local specID = Utils.LootSpecID and Utils.LootSpecID()
    for _, reward in ipairs(type(info) == "table" and type(info.rewards) == "table" and info.rewards or {}) do
        if type(reward) == "table" and reward.type == itemType and Utils.IsUsableNumber(reward.id) then
            local tier = BGV.Bis and BGV.Bis.Tier(reward.id, specID)
            local level = 0
            if reward.itemDBID and C_WeeklyRewards and C_WeeklyRewards.GetItemHyperlink and C_Item and C_Item.GetDetailedItemLevelInfo then
                local link = Utils.Call(C_WeeklyRewards.GetItemHyperlink, reward.itemDBID)
                level = link and Utils.Call(C_Item.GetDetailedItemLevelInfo, link) or 0
            end
            best = max(best, (TIER_RANK[tier] or 0) * 1000 + (Utils.IsUsableNumber(level) and level or 0))
        end
    end
    return best
end

-- The vault's slots that are done (claim week: holding a reward), not counting Collect itself; some
-- may still be opening or closing.
local function Slots(vault, claim)
    local list = {}
    local concession = Enum and Enum.WeeklyRewardChestThresholdType and Enum.WeeklyRewardChestThresholdType.Concession
    local rewards = vault.ConcessionsFrame and vault.ConcessionsFrame.Rewards
    for _, activityFrame in ipairs(type(vault.Activities) == "table" and vault.Activities or {}) do
        local isCollect = (concession and activityFrame.type == concession) or (rewards and activityFrame:GetParent() == rewards)
        local done
        if claim then
            done = activityFrame.hasRewards == true
        else
            done = activityFrame.bgvSlot ~= nil and activityFrame.bgvSlot.unlocked == true and activityFrame.bgvFX ~= nil
        end
        if not isCollect and done and activityFrame:IsShown() then
            list[#list + 1] = activityFrame
        end
    end
    return list
end

function Begin(activityFrame, moodName, claim, button)
    local fx = Case.Ensure(activityFrame)
    local face = activityFrame.bgvFace or Build(activityFrame, fx)
    if face.active then
        -- pointed at again while it was cheering up: back to how it felt
        face.entering, face.left = true, 0
        return
    end
    face.mood = MOODS[moodName]
    face.moodName = moodName
    face.claim = claim
    face.handBack = nil
    face.active, face.entering, face.shown = true, true, false
    face.t, face.left, face.show, face.sad, face.relief, face.gate = 0, 0, 0, 0, 0, 0
    face.blinkIn, face.blinkAt = Random(1.5, 3.5), nil
    face.nextTear, face.tearSide, face.held = 0.4, nil, false
    -- the eyes look at Collect (sideways for the sulking one), or up, pleading
    local lookX, lookY = 0, -1.5
    local bx, by = button and button.GetCenter and button:GetCenter()
    local sx, sy = activityFrame:GetCenter()
    if bx and by and sx and sy then
        local dx, dy = bx - sx, by - sy
        local length = sqrt(dx * dx + dy * dy)
        if length > 1 then
            local reach = face.mood.look == "button" and 2.5 or 1.6
            lookX, lookY = dx / length * reach, dy / length * reach
        end
    end
    if face.mood.look == "up" then
        lookX, lookY = 0, 2
    end
    face.lookX, face.lookY = lookX, lookY
    if claim then
        -- the gates close over the reward while Collect is pointed at, above the vault's glow
        Case.RaiseAboveGlow(activityFrame)
        local atlas = Case.FaceAtlas(activityFrame)
        for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
            if gate.face.SetAtlas then
                gate.face:SetAtlas(atlas)
            end
            gate:SetAlpha(1)
        end
        K.SlotSize(fx)
        K.Levels(fx, false)
        K.GateLayout(fx, "rows")
        K.FaceMode(fx, "wipe")
        -- a reward's case (Case.OpenClaim) has just shut its gates, or one waiting for its reward
        -- is shut (Case.Cover): the face forms on them
        face.handBack = Case.HasClaim(activityFrame) or Case.IsCovered(activityFrame)
        if face.handBack then
            face.gate = 1
            K.Doors(fx, fx.slotHeight / 2, fx.slotHeight / 2)
        else
            K.Doors(fx, 0, 0)
        end
    else
        Case.FadeCaption(activityFrame, 0)
    end
    face.layer:SetFrameLevel(fx.topDoor:GetFrameLevel() + 2)
    face.layer:Show()
    faces[#faces + 1] = face
end

-- --- what UI.lua calls ----------------------------------------------------------------------------------------

-- Collect is pointed at: the done slots' gates turn sad, the best reward's taking it hardest.
function Faces.Start(button)
    local vault = WeeklyRewardsFrame
    if not Enabled() or not vault or not vault:IsShown() then
        return
    end
    local claim = not ProgressWeek()
    local slots = Slots(vault, claim)
    if #slots == 0 then
        return
    end
    pointedAt, pointedClaim = button, claim
    local worth, order = {}, {}
    for _, activityFrame in ipairs(slots) do
        worth[activityFrame] = Worth(activityFrame, claim)
        order[activityFrame] = math.random()
    end
    table.sort(slots, function(a, b)
        if worth[a] ~= worth[b] then
            return worth[a] > worth[b]
        end
        return order[a] < order[b]
    end)
    for rank, activityFrame in ipairs(slots) do
        local moodName
        if rank == 1 then
            moodName = "wail"
        elseif rank == #slots then
            moodName = "sulk"
        else
            moodName = MIDDLE[(rank - 2) % #MIDDLE + 1]
        end
        if claim and Case.HasClaim(activityFrame) then
            -- open onto its reward: it closes first
            Case.SuspendClaim(activityFrame)
        end
        if Case.IsAnimating(activityFrame) then
            -- still opening or closing (pointed at a moment ago): it cries once its gates are shut
            waiting[activityFrame] = moodName
        else
            waiting[activityFrame] = nil
            Begin(activityFrame, moodName, claim, button)
        end
    end
    if not driver then
        driver = CreateFrame("Frame")
    end
    driver:SetScript("OnUpdate", Drive)
end

-- Collect is no longer pointed at: the faces cheer up and go.
function Faces.Leave()
    pointedAt = nil
    for activityFrame in pairs(waiting) do
        waiting[activityFrame] = nil
        if Case.HasClaim(activityFrame) then
            Case.ResumeClaim(activityFrame)
        end
    end
    for _, face in ipairs(faces) do
        face.entering = false
    end
end

-- The vault closed: every face goes at once.
function Faces.Stop()
    pointedAt = nil
    for activityFrame in pairs(waiting) do
        waiting[activityFrame] = nil
    end
    for index = #faces, 1, -1 do
        Finish(faces[index], true)
        faces[index] = nil
    end
    if driver then
        driver:SetScript("OnUpdate", nil)
    end
end

function Faces.IsShowing()
    return #faces > 0
end

-- Hooks Collect (the vault's concession rewards): pointing at one, and leaving it.
function Faces.Hook(vault)
    local rewards = vault and vault.ConcessionsFrame and vault.ConcessionsFrame.Rewards
    if not rewards or type(rewards.GetChildren) ~= "function" then
        return
    end
    for _, button in ipairs({ rewards:GetChildren() }) do
        if button.HookScript and not button.bgvFaceHook then
            button.bgvFaceHook = true
            button:HookScript("OnEnter", Utils.Protect("sad gates", function(self)
                Faces.Start(self)
            end))
            button:HookScript("OnLeave", Utils.Protect("sad gates", function()
                Faces.Leave()
            end))
        end
    end
end
