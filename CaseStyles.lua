local _, BGV = ...

-- The specializations' opening styles (Case.lua has the engine and the first few). Styles of a kind
-- share how they open: the face cut into pieces, a line that wipes it away, a hole that grows, or
-- gates that slide or fade; each specialization has its own look and moments on top. Like Case.lua's,
-- a style makes its textures the first time a slot uses it, and its effects come from the slot's pool.
local Case = BGV.Case
local K = Case.kit

local MEDIA = K.MEDIA
local GATE_CORNER = K.GATE_CORNER
local CASE_STRIDE = K.CASE_STRIDE
local Clamp01, Smooth, EaseOutCubic, EaseInCubic = K.Clamp01, K.Smooth, K.EaseOutCubic, K.EaseInCubic
local EaseInOut, EaseOutBack, EaseOutBounce = K.EaseInOut, K.EaseOutBack, K.EaseOutBounce
local Random, Spawn, MoveReel, DressCells = K.Random, K.Spawn, K.MoveReel, K.DressCells
local sin, cos, abs, max, min, pi = math.sin, math.cos, math.abs, math.max, math.min, math.pi
local atan2 = math.atan2 or math.atan

-- The effects: Case.lua's, and these. Four-shape sheets (`shapes`) pick one at random, mirrored and
-- turned, like Case.lua's clouds; `align` turns a spark along its flight.
K.KINDS.drop = { file = MEDIA .. "CaseDrop", blend = "BLEND" }
K.KINDS.leaf = { file = MEDIA .. "CaseLeaf", blend = "BLEND", spin = true }
K.KINDS.petal = { file = MEDIA .. "CasePetal", blend = "BLEND", spin = true }
K.KINDS.bubble = { file = MEDIA .. "CaseBubble", blend = "BLEND" }
K.KINDS.grain = { file = MEDIA .. "CaseDisc", blend = "BLEND" }
K.KINDS.soul = { file = MEDIA .. "CaseSoul", blend = "ADD" }
K.KINDS.spark = { file = MEDIA .. "CaseSpark", blend = "ADD", align = true }
K.KINDS.smoke = { file = MEDIA .. "CaseSmoke", blend = "BLEND", shapes = 4, tilt = 3.1, turn = 0.5, stretch = 0.2 }
K.KINDS.foam = { file = MEDIA .. "CaseFoam", blend = "BLEND", shapes = 4, tilt = 3.1, turn = 0.4, stretch = 0.1 }
K.KINDS.chip = { file = MEDIA .. "CaseChips", blend = "BLEND", shapes = 4, tilt = 3.1, turn = 7, stretch = 0.25 }
K.KINDS.bone = { file = MEDIA .. "CaseBones", blend = "BLEND", shapes = 4, tilt = 3.1, turn = 9, stretch = 0.08 }

-- --- helpers ----------------------------------------------------------------------------------------------

-- A style's textures, made the first time the slot uses it; everything in `art.list` hides at rest.
local function Art(fx, id, build)
    fx.styleArt = fx.styleArt or {}
    local art = fx.styleArt[id]
    if not art then
        art = { list = {} }
        build(fx, art)
        fx.styleArt[id] = art
    end
    return art
end

local function Tex(art, parent, file, blend, r, g, b, layer, sub)
    local texture = parent:CreateTexture(nil, layer or "OVERLAY", nil, sub or 0)
    if file then
        texture:SetTexture(MEDIA .. file)
    end
    if blend then
        texture:SetBlendMode(blend)
    end
    if r then
        texture:SetVertexColor(r, g, b)
    end
    texture:Hide()
    art.list[#art.list + 1] = texture
    return texture
end

-- Shows and hides a style's texture, only when that changes.
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

-- Shows `texture` centred (x, y) from the slot's centre (up is +y), `w` by `h`.
local function Put(fx, texture, x, y, w, h, alpha)
    texture:SetPoint("CENTER", fx, "CENTER", x, y)
    texture:SetSize(w, h or w)
    texture:SetAlpha(alpha or 1)
    Show(texture)
end

-- `texture` turned to `angle` (a square, so it turns without stretching), or hidden at no alpha.
local function PutTurned(fx, texture, x, y, size, angle, alpha)
    if alpha <= 0 then
        Off(texture)
        return
    end
    texture:SetRotation(angle)
    Put(fx, texture, x, y, size, size, alpha)
end

-- Shows art drawn upright turned a quarter: clockwise (its top to the right) or not (to the left).
local function Quarter(texture, clockwise)
    if clockwise then
        texture:SetTexCoord(0, 1, 1, 1, 0, 0, 1, 0)
    else
        texture:SetTexCoord(1, 0, 0, 0, 1, 1, 0, 1)
    end
end

local function Part(fx, kind, x, y, vx, vy, life, size, r, g, b, alpha)
    local p = Spawn(fx, kind, x, y, vx, vy, life, size)
    if p then
        p.texture:SetVertexColor(r, g, b)
        p.alpha = alpha or 1
    end
    return p
end

local function Chance(rate, dt)
    return math.random() < rate * dt
end

-- A burst of `n` effects from (x, y), every direction, `low` to `high` a second.
local function Burst(fx, kind, n, x, y, low, high, life, size, r, g, b, alpha)
    for _ = 1, n do
        local a = Random(0, pi * 2)
        local speed = Random(low, high)
        local p = Part(fx, kind, x, y, cos(a) * speed, sin(a) * speed, Random(life * 0.7, life), Random(size * 0.7, size), r, g, b, alpha)
        if p then
            p.drag = 0.94
        end
    end
end

-- Sparks streaking from (x, y) around `angle`, `spread` either side, falling by `fall`.
local function Sparks(fx, n, x, y, angle, spread, low, high, r, g, b, fall, life)
    life = life or 0.45
    for _ = 1, n do
        local a = angle + Random(-spread, spread)
        local speed = Random(low, high)
        local p = Part(fx, "spark", x, y, cos(a) * speed, sin(a) * speed, Random(life * 0.6, life), Random(10, 15), r, g, b)
        if p then
            p.g, p.drag, p.grow = -(fall or 0), 0.95, -0.5
        end
    end
end

-- Bits knocked off the gates: chips in the face's colors (or r, g, b), tumbling down.
local function Chips(fx, n, x, y, low, high, spreadX, r, g, b)
    for _ = 1, n do
        local a = Random(0, pi * 2)
        local speed = Random(low, high)
        local p = Part(fx, "chip", x + Random(-spreadX, spreadX), y, cos(a) * speed, sin(a) * speed + 40, Random(0.55, 0.85), Random(5, 8),
            r or 0.86, g or 0.68, b or 0.42)
        if p then
            p.g, p.grow, p.late = -560, 0, true
        end
    end
end

local function Smoke(fx, x, y, vx, vy, life, size, alpha, r, g, b)
    local p = Part(fx, "smoke", x, y, vx, vy, life, size, r, g, b, alpha)
    if p then
        p.drag, p.grow = 0.97, 0.7
    end
    return p
end

-- A ring spreading from (x, y) since `at` (GetTime(); nil: none), over `life`: from `from` to `to`
-- across, `squash` its height against its width.
local function Ring(fx, texture, at, life, x, y, from, to, squash, alpha)
    local age = at and (GetTime() - at) or -1
    if age < 0 or age >= life then
        Off(texture)
        return
    end
    local size = from + (to - from) * EaseOutCubic(age / life)
    Put(fx, texture, x, y, size, size * (squash or 1), (alpha or 1) * (1 - age / life))
end

-- A flash that fades over `life` since `at` (GetTime(); nil: none).
local function Flash(fx, texture, at, life, x, y, w, h, alpha)
    local age = at and (GetTime() - at) or -1
    if age < 0 or age >= life then
        Off(texture)
        return
    end
    local k = age / life
    Put(fx, texture, x, y, w * (1 + 0.3 * k), h * (1 + 0.3 * k), (alpha or 1) * (1 - k) * (1 - k))
end

-- How much of a short glow is left, `life` seconds after `at` (GetTime(); nil: none).
local function Since(at, life)
    if not at then
        return 0
    end
    local age = GetTime() - at
    if age < 0 or age >= life then
        return 0
    end
    return 1 - age / life
end

-- The look every style sets up: the reel's shade, the marker, the tier colors' strength.
local function Mood(fx, shade, marker, backs)
    K.ColorTexture(fx.shade, shade[1], shade[2], shade[3], 1)
    K.MarkerTint(fx, marker[1], marker[2], marker[3])
    K.CellBacksAlpha(fx, backs or 0.8)
end

-- Rest: the style's art put away, then what every style leaves behind.
local function Rest(id, extra)
    return function(fx)
        local art = fx.styleArt and fx.styleArt[id]
        if art then
            for _, region in ipairs(art.list) do
                region:Hide()
                region.bgvOn = false
            end
            if extra then
                extra(fx, art)
            end
        end
        K.RestCommon(fx)
    end
end

local function Register(id, name, class, spec, style)
    Case.AddStyle({ id = id, name = name, class = class, spec = spec }, style)
end

-- --- pieces: the face cut along mask files, the pieces flying apart and coming back to close ----------------

-- def: files (the masks), moves (per piece: vx, vy, g down, delay), split (when it breaks), flyFor
-- (when the pieces are gone), fadeFrom, fadeFor, openFor, closeFor, Build, Enter, Split, Join,
-- Update(fx, art, dt). Each piece keeps where it is (x, y) for the style's own effects.
local function PieceStyle(id, def)
    local function Build(fx, art)
        local frame = CreateFrame("Frame", nil, fx)
        frame:SetAllPoints(fx)
        frame:EnableMouse(false)
        frame:Hide()
        art.list[#art.list + 1] = frame
        art.frame = frame
        art.pieces = {}
        for index, file in ipairs(def.files) do
            local texture = frame:CreateTexture(nil, "ARTWORK")
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(MEDIA .. file, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            texture:AddMaskTexture(mask)
            art.pieces[index] = { texture = texture, mask = mask, x = 0, y = 0 }
        end
        if def.Build then
            def.Build(fx, art)
        end
    end
    -- The pieces `tau` seconds after the split (0: the face whole).
    local function Place(fx, art, tau)
        for index, piece in ipairs(art.pieces) do
            local move = def.moves[index]
            local s = max(0, tau - (move.delay or 0))
            local x = move.vx * s
            local y = move.vy * s - 0.5 * (move.g or 0) * s * s
            piece.x, piece.y = x, y
            piece.texture:SetPoint("CENTER", fx, "CENTER", x, y)
            piece.mask:SetPoint("CENTER", fx, "CENTER", x, y)
            piece.texture:SetAlpha(1 - Clamp01((s - (def.fadeFrom or 0.2)) / (def.fadeFor or 0.3)))
        end
    end
    local style = {
        openFor = def.openFor,
        closeFor = def.closeFor,
        Enter = function(fx)
            local art = Art(fx, id, Build)
            K.Levels(fx, false)
            K.FaceMode(fx, "wipe")
            K.DoorsClosed(fx)
            K.Seams(fx, nil)
            art.frame:SetFrameLevel(fx.level + 8)
            local atlas = K.FaceAtlas(fx.owner)
            local w, h = fx.slotWidth, fx.slotHeight
            for _, piece in ipairs(art.pieces) do
                if piece.texture.SetAtlas then
                    piece.texture:SetAtlas(atlas)
                end
                piece.texture:SetVertexColor(1, 1, 1)
                piece.texture:SetSize(w, h)
                piece.mask:SetSize(w, h)
            end
            Place(fx, art, 0)
            def.Enter(fx, art)
        end,
        Update = function(fx, dt)
            local art = fx.styleArt[id]
            local t, flags = fx.t, fx.flags
            if fx.phase == "opening" then
                if t >= def.split then
                    if not flags.split then
                        flags.split = true
                        K.Doors(fx, 0, 0)
                        art.frame:Show()
                        def.Split(fx, art)
                    end
                    Place(fx, art, t - def.split)
                end
            elseif fx.phase == "open" then
                if fx.entered then
                    art.frame:Hide()
                    K.Doors(fx, 0, 0)
                end
            else
                -- the pieces fly back together, and the gates close behind them
                local back = def.closeFor - 0.1
                if t < back then
                    if fx.entered then
                        art.frame:Show()
                    end
                    local k = Clamp01(t / (back * 0.85))
                    Place(fx, art, def.flyFor * (1 - Smooth(k)))
                    -- whole again: the gates close under the pieces, so no seam shows between them
                    if k >= 1 then
                        K.DoorsClosed(fx)
                    end
                elseif not flags.joined then
                    flags.joined = true
                    art.frame:Hide()
                    K.DoorsClosed(fx)
                    if def.Join then
                        def.Join(fx, art)
                    end
                end
            end
            def.Update(fx, art, dt)
        end,
        Rest = Rest(id, def.Rest),
    }
    return style
end

-- The pieces tinted (scorched, frozen, glowing).
local function TintPieces(art, r, g, b)
    for _, piece in ipairs(art.pieces) do
        piece.texture:SetVertexColor(r, g, b)
    end
end

-- --- wipes: a line crosses the slot, the face on one side of it ------------------------------------------------

-- def.dir: "up" (the line rises from the bottom, the face above it), "down" (it falls from the top,
-- the face below) or "right" (it crosses to the right, the face right of it). def.delay and
-- def.travel time the opening; closing runs it back over def.back (from def.backDelay). def.edge:
-- the line's art (file, tint, blend, thick, tile: UI units one texture width covers, flip, shift).
local function WipeStyle(id, def)
    local edge = def.edge
    local function Build(fx, art)
        if edge then
            local texture = Tex(art, fx.top, nil, edge.blend or "BLEND", edge.r, edge.g, edge.b)
            if def.dir == "right" then
                texture:SetTexture(MEDIA .. edge.file, "CLAMP", "REPEAT")
            else
                texture:SetTexture(MEDIA .. edge.file, "REPEAT", "CLAMP")
            end
            art.edge = texture
        end
        if def.Build then
            def.Build(fx, art)
        end
    end
    -- u: how much of the slot is open (0 to 1). Returns the line's place: x from the slot's left
    -- (sideways) or y up from its centre.
    local function Wipe(fx, art, u, dt)
        local w, h = fx.slotWidth, fx.slotHeight
        local pad = 10
        art.scroll = ((art.scroll or 0) + dt * (edge and edge.scroll or 0.3)) % 1
        if def.dir == "right" then
            local x = -pad + (w + 2 * pad) * u
            K.Doors(fx, max(0, min(w, w - x)), 0)
            if art.edge then
                if x > -8 and x < w + 8 then
                    art.edge:SetPoint("CENTER", fx, "LEFT", x, 0)
                    art.edge:SetSize(edge.thick, h + 8)
                    art.edge:SetTexCoord(0, 1, art.scroll, art.scroll + (h + 8) / edge.tile)
                    Show(art.edge)
                else
                    Off(art.edge)
                end
            end
            return x
        end
        local line -- down from the top of the slot
        if def.dir == "up" then
            line = h + pad - (h + 2 * pad) * u
            K.Doors(fx, max(0, min(h, line)), 0)
        else
            line = -pad + (h + 2 * pad) * u
            K.Doors(fx, 0, max(0, min(h, h - line)))
        end
        if art.edge then
            if line > -8 and line < h + 8 then
                local top, bottom = 0, 1
                if edge.flip then
                    top, bottom = 1, 0
                end
                art.edge:SetPoint("CENTER", fx, "TOP", 0, -line + (edge.shift or 0))
                art.edge:SetSize(w + 8, edge.thick)
                art.edge:SetTexCoord(art.scroll, art.scroll + (w + 8) / edge.tile, top, bottom)
                Show(art.edge)
            else
                Off(art.edge)
            end
        end
        return h / 2 - line
    end
    return {
        openFor = def.openFor,
        closeFor = def.closeFor,
        Enter = function(fx)
            local art = Art(fx, id, Build)
            K.Levels(fx, false)
            K.GateLayout(fx, def.dir == "right" and "right" or "rows")
            K.FaceMode(fx, "wipe")
            K.DoorsClosed(fx)
            K.Seams(fx, nil)
            art.scroll = 0
            def.Enter(fx, art)
        end,
        Update = function(fx, dt)
            local art = fx.styleArt[id]
            local t = fx.t
            local u
            if fx.phase == "opening" then
                u = (def.ease or EaseInOut)((t - def.delay) / def.travel)
            elseif fx.phase == "open" then
                u = 1
            else
                u = 1 - (def.backEase or EaseInOut)((t - (def.backDelay or 0)) / def.back)
            end
            if def.Wobble then
                u = def.Wobble(fx, u)
            end
            local at = Wipe(fx, art, Clamp01(u), dt)
            def.Update(fx, art, dt, u, at)
        end,
        Rest = Rest(id, def.Rest),
    }
end

-- --- holes: the face opens from a hole that grows, the reel showing through it --------------------------------

-- def.shape: a mask file (nil: a circle), def.fill: how much of the mask's half-size the shape
-- surely covers, def.Radius(fx, art) -> the hole's radius (and its height, for an ellipse) this frame.
local function HoleStyle(id, def)
    local fill = def.fill or 1
    return {
        openFor = def.openFor,
        closeFor = def.closeFor,
        Enter = function(fx)
            local art = Art(fx, id, def.Build)
            K.Levels(fx, true)
            K.FaceMode(fx, "wipe")
            K.DoorsClosed(fx)
            K.Seams(fx, nil)
            local w, h = fx.slotWidth, fx.slotHeight
            fx.rmax = math.sqrt(w * w + h * h) / 2 + 8
            K.MaskShape(fx, def.shape and (MEDIA .. def.shape) or nil)
            K.MaskOn(fx, unpack(def.Masked and def.Masked(art) or {}))
            K.MaskCircle(fx, 0, 0, 0)
            def.Enter(fx, art)
        end,
        Update = function(fx, dt)
            local art = fx.styleArt[id]
            local rx, ry = def.Radius(fx, art)
            rx = max(0, rx)
            ry = max(0, ry or rx)
            K.MaskCircle(fx, 0, 0, rx / fill, ry / fill)
            def.Update(fx, art, dt, rx, ry)
        end,
        Rest = Rest(id, def.Rest),
    }
end

-- --- gates that slide apart: top and bottom ("rows") or left and right ("columns") -----------------------------

-- def.Reveal(fx, art) -> how far each gate has gone (0: shut, 1: open), top/left then bottom/right.
-- def.Update gets how much each gate still covers.
local function SlideStyle(id, def)
    return {
        openFor = def.openFor,
        closeFor = def.closeFor,
        Enter = function(fx)
            local art = Art(fx, id, def.Build)
            K.Levels(fx, false)
            K.GateLayout(fx, def.columns and "columns" or "rows")
            K.FaceMode(fx, "slide")
            K.DoorsClosed(fx)
            K.Seams(fx, nil)
            def.Enter(fx, art)
        end,
        Update = function(fx, dt)
            local art = fx.styleArt[id]
            local a, b = def.Reveal(fx, art)
            b = b or a
            local w, h = fx.slotWidth, fx.slotHeight
            local ca, cb
            if def.columns then
                ca, cb = w / 2 * (1 - a), w / 2 * (1 - b)
            else
                -- like Vault Door, the gates stop at the reel's window, the slot's edges still showing
                ca = GATE_CORNER + (h / 2 - GATE_CORNER) * (1 - a)
                cb = GATE_CORNER + (h / 2 - GATE_CORNER) * (1 - b)
            end
            K.Doors(fx, max(0, ca), max(0, cb))
            if def.seams then
                if ca > 1 and cb > 1 and not def.columns then
                    K.Seams(fx, ca, cb)
                else
                    K.Seams(fx, nil)
                end
            end
            def.Update(fx, art, dt, ca, cb)
        end,
        Rest = Rest(id, def.Rest),
    }
end

-- --- gates that stay, and fade -----------------------------------------------------------------------------------

local function StillStyle(id, def)
    return {
        openFor = def.openFor,
        closeFor = def.closeFor,
        Enter = function(fx)
            local art = Art(fx, id, def.Build)
            fx.doorsAlpha = nil
            K.Levels(fx, false)
            K.FaceMode(fx, def.faceMode or "wipe")
            K.DoorsClosed(fx)
            K.Seams(fx, nil)
            def.Enter(fx, art)
        end,
        Update = function(fx, dt)
            def.Update(fx, fx.styleArt[id], dt)
        end,
        Rest = Rest(id, def.Rest),
    }
end

local function DoorsAlpha(fx, alpha)
    if fx.doorsAlpha == alpha then
        return
    end
    fx.doorsAlpha = alpha
    fx.topDoor:SetAlpha(alpha)
    fx.bottomDoor:SetAlpha(alpha)
    if alpha <= 0.01 then
        K.Doors(fx, 0, 0)
    else
        K.DoorsClosed(fx)
    end
end

-- How visible the gates are: fading out from `from` over `over`, and back in once closing.
local function Fade(fx, from, over, backFrom, backOver)
    if fx.phase == "opening" then
        return 1 - Smooth((fx.t - from) / over)
    elseif fx.phase == "open" then
        return 0
    end
    return Smooth((fx.t - backFrom) / backOver)
end

-- How far the reel has come in from the dark: each item by its distance from the marker.
local function FadeIcons(fx, amount)
    local marker = fx.windowWidth / 2 + 1
    for index, cell in ipairs(fx.cells) do
        local center = (fx.offset or 0) + (index - 0.5) * CASE_STRIDE
        local delay = abs(center - marker) / fx.windowWidth * 0.6
        local alpha = Clamp01((amount - delay) / 0.4)
        cell.icon:SetAlpha(alpha)
        cell.back:SetAlpha(alpha * 0.8)
    end
end

-- A drifting layer of fog (or smoke) over the slot: `layer` scrolls by (du, dv) a second.
local function Drift(fx, texture, dt, du, dv, x, y, w, h, alpha)
    texture.bgvU = ((texture.bgvU or 0) + du * dt) % 1
    texture.bgvV = ((texture.bgvV or 0) + dv * dt) % 1
    local u, v = texture.bgvU, texture.bgvV
    texture:SetTexCoord(u, u + w / 300, v, v + h / 300)
    if alpha <= 0 then
        Off(texture)
    else
        Put(fx, texture, x, y, w, h, alpha)
    end
end

-- =============================================================================================================
-- The face cut into pieces
-- =============================================================================================================

-- The masks' lines, in the slot's units (make_spec_media.py draws them the same way).
local SLOT_W, SLOT_H = 219, 126
local CUT = -atan2(SLOT_H, SLOT_W * 0.7) -- Mortal Strike: down to the right
local DIAGONAL = atan2(SLOT_H, SLOT_W) -- Rampage: the slot's diagonals
local CAT = math.rad(64) -- Cat Claw: three claws, up to the right
local BEAR = math.rad(38) -- Bear Maul: four, wide and low
local X_PIECES = { "CaseCutN", "CaseCutE", "CaseCutS", "CaseCutW" }

-- A blade's slash: its colored glow and white-hot edge, through (x, y) along `angle`.
local function Slash(fx, glow, core, x, y, length, angle, alpha)
    PutTurned(fx, glow, x, y, length, angle, alpha)
    PutTurned(fx, core, x, y, length, angle, alpha)
end

-- How a slash shows `age` seconds after it lands: a quick flash, then fading.
local function SlashAlpha(age)
    if age < 0 then
        return 0
    elseif age < 0.04 then
        return age / 0.04
    end
    return 1 - Clamp01((age - 0.04) / 0.3)
end

-- Sparks along a line through (x, y) at `angle`, thrown off to both sides.
local function SparksAlong(fx, n, x, y, angle, length, r, g, b, fall)
    local dx, dy = cos(angle), sin(angle)
    for _ = 1, n do
        local along = Random(-length / 2, length / 2)
        local side = math.random() < 0.5 and -1 or 1
        Sparks(fx, 1, x + dx * along, y + dy * along, angle + side * pi / 2, 0.6, 90, 240, r, g, b, fall or 250)
    end
end

-- The reel waits for the split, races off, and settles to `cruise`; closing, it slows to a stop.
local function SplitSpeed(fx, split, cruise, rush)
    if fx.phase == "opening" then
        if fx.t < split then
            return 0
        end
        return cruise + rush * (1 - Clamp01((fx.t - split) / 0.5))
    elseif fx.phase == "closing" then
        return cruise * (1 - Clamp01(fx.t / 0.4))
    end
    return cruise
end

-- --- Mortal Strike (Arms warrior): a glint scores the line, one heavy cut; the halves part on glowing edges ---------

Register("arms", "Mortal Strike", "WARRIOR", 71, PieceStyle("arms", {
    files = { "CaseCutA", "CaseCutB" },
    moves = {
        -- the upper half up the cut, pushed a little off it; the lower half down it
        { vx = -cos(CUT) * 150 - sin(CUT) * 25, vy = -sin(CUT) * 150 + cos(CUT) * 25, g = 160 },
        { vx = cos(CUT) * 150, vy = sin(CUT) * 150, g = 260 },
    },
    split = 0.3, flyFor = 0.6, fadeFrom = 0.15, fadeFor = 0.35, openFor = 0.95, closeFor = 0.55,
    Build = function(fx, art)
        art.score = Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 0.7, 0.4, "OVERLAY", 1)
        art.glow = Tex(art, fx.top, "CaseSlashArc", "ADD", 1, 0.5, 0.2, "OVERLAY", 2)
        art.core = Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 0.95, 0.85, "OVERLAY", 3)
        art.glint = Tex(art, fx.top, "CaseSparkle", "ADD", 1, 0.95, 0.85, "OVERLAY", 4)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.85, 0.7, "OVERLAY", 5)
        art.edges = {
            Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 0.45, 0.12, "OVERLAY", 1),
            Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 0.45, 0.12, "OVERLAY", 1),
        }
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.02, 0.02 }, { 1, 0.35, 0.25 })
        K.EnsureGhosts(fx)
        art.flashAt, art.weldAt = nil, nil
    end,
    Split = function(fx, art)
        fx.shake = 1.6
        art.flashAt = GetTime()
        SparksAlong(fx, 14, 0, 0, CUT, 190, 1, 0.8, 0.45)
        Chips(fx, 6, 0, 0, 40, 120, 40)
    end,
    Join = function(fx, art)
        fx.shake = 1
        art.weldAt = GetTime()
        SparksAlong(fx, 8, 0, 0, CUT, 150, 1, 0.8, 0.45)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local dx, dy = cos(CUT), sin(CUT)
        if fx.phase == "opening" then
            -- a glint runs along the edge-to-be and scores it
            local path = w * 0.95
            if t < 0.24 then
                local k = Clamp01(t / 0.22)
                local along = (k - 0.5) * path
                art.glint:SetRotation(t * 8)
                Put(fx, art.glint, dx * along, dy * along, 20, 20, sin(pi * k))
                local mid, length = (along - path / 2) / 2, along + path / 2
                PutTurned(fx, art.score, dx * mid, dy * mid, max(1, length * 1.06), CUT, 0.4 * k)
            else
                Off(art.glint)
                Off(art.score)
            end
            -- the blade comes down through it, sweeping into line
            local age = t - 0.24
            local sweep = 0.14 * (1 - EaseOutCubic(Clamp01(age / 0.07)))
            Slash(fx, art.glow, art.core, 0, 0, w * 1.3, CUT + sweep, SlashAlpha(age))
            -- the halves part on red-hot edges
            if fx.flags.split then
                local heat = 1 - Clamp01((t - 0.3) / 0.45)
                for index, edge in ipairs(art.edges) do
                    local piece = art.pieces[index]
                    PutTurned(fx, edge, piece.x, piece.y, w * 1.25, CUT, heat * 0.9)
                end
            end
        else
            Off(art.glow)
            Off(art.core)
            Off(art.score)
            Off(art.glint)
            -- closing: the halves weld back together, glowing for a moment
            PutTurned(fx, art.edges[1], 0, 0, w * 1.25, CUT, Since(art.weldAt, 0.3))
            Off(art.edges[2])
        end
        Flash(fx, art.flash, art.flashAt, 0.18, 0, 0, w * 1.2, h * 1.2, 0.55)
        MoveReel(fx, SplitSpeed(fx, 0.3, 95, 500), dt)
        DressCells(fx, 0.1, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Rampage (Fury warrior): rage reddens the gates, four cuts in a blur, and they burst in four pieces -------------

local RAMPAGE_CUTS = { { 0.06, DIAGONAL, 1.35 }, { 0.12, -DIAGONAL, 1.35 }, { 0.18, 0.12, 1.0 }, { 0.24, pi / 2 - 0.25, 0.75 } }

Register("fury", "Rampage", "WARRIOR", 72, PieceStyle("fury", {
    files = X_PIECES,
    moves = {
        { vx = 0, vy = 190, g = 560 },
        { vx = 220, vy = 70, g = 560, delay = 0.02 },
        { vx = 0, vy = -60, g = 560 },
        { vx = -220, vy = 70, g = 560, delay = 0.02 },
    },
    split = 0.3, flyFor = 0.55, fadeFrom = 0.18, fadeFor = 0.3, openFor = 0.9, closeFor = 0.5,
    Build = function(fx, art)
        art.glows, art.cores = {}, {}
        for index = 1, #RAMPAGE_CUTS do
            art.glows[index] = Tex(art, fx.top, "CaseSlashArc", "ADD", 1, 0.16, 0.08, "OVERLAY", 2)
            art.cores[index] = Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 0.75, 0.6, "OVERLAY", 3)
        end
        art.rage = Tex(art, fx.mid, "CaseGlow", "ADD", 1, 0.12, 0.04)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.25, 0.12, "OVERLAY", 4)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.35, 0.2, "OVERLAY", 5)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.07, 0.01, 0.01 }, { 1, 0.2, 0.15 })
        K.EnsureGhosts(fx)
        art.hitAt, art.burstAt = nil, nil
    end,
    Split = function(fx, art)
        fx.shake = 2
        art.burstAt = GetTime()
        Sparks(fx, 16, 0, 0, 0, pi, 120, 280, 1, 0.35, 0.2, 200)
        Chips(fx, 8, 0, 0, 60, 160, 30)
    end,
    Join = function(fx, art)
        fx.shake = 1.2
        art.hitAt = GetTime()
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            -- each cut sweeps in, flashes the gates and shakes them harder
            for index, cut in ipairs(RAMPAGE_CUTS) do
                local age = t - cut[1]
                local side = index % 2 == 0 and -1 or 1
                local sweep = side * 0.2 * (1 - EaseOutCubic(Clamp01(age / 0.06)))
                Slash(fx, art.glows[index], art.cores[index], 0, 0, w * cut[3], cut[2] + sweep, SlashAlpha(age))
                if age >= 0 and not fx.flags[index] then
                    fx.flags[index] = true
                    fx.shake = 0.6 + 0.25 * index
                    art.hitAt = GetTime()
                    SparksAlong(fx, 5, 0, 0, cut[2], 80, 1, 0.4, 0.25, 150)
                end
            end
            Put(fx, art.rage, 0, 0, w * 1.1, h * 1.2, Clamp01(t / 0.2) * (0.3 + 0.1 * sin(t * 30)))
            -- the gates redden with the rage, flaring at each cut
            if t < 0.3 then
                local flare = Since(art.hitAt, 0.12)
                K.FaceTint(fx, 1, 0.82 - 0.3 * flare, 0.78 - 0.35 * flare)
            end
        else
            for index in ipairs(RAMPAGE_CUTS) do
                Off(art.glows[index])
                Off(art.cores[index])
            end
            local pulse = fx.phase == "open" and 0.12 + 0.06 * sin(GetTime() * 5) or 0.12 * (1 - Clamp01(t / 0.3))
            Put(fx, art.rage, 0, 0, w * 1.1, h * 1.2, pulse)
            if fx.phase == "open" and Chance(6, dt) then
                local p = Part(fx, "spark", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-8, 8), Random(30, 60),
                    Random(0.6, 1), Random(9, 12), 1, 0.25, 0.1, 0.8)
                if p then
                    p.grow = -0.4
                end
            end
        end
        Ring(fx, art.ring, art.burstAt, 0.35, 0, 0, 40, 300, 0.7)
        Flash(fx, art.flash, art.burstAt or art.hitAt, 0.2, 0, 0, w, h, 0.6)
        MoveReel(fx, SplitSpeed(fx, 0.3, 130, 700), dt)
        DressCells(fx, 0.08, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Cat Claw (Feral druid): eyes in the dark, one swipe of three claws; the strips fall away bleeding ----------------

local CAT_OFFSETS = { -34, 0, 34 }

local function Bleed(fx, n)
    for _ = 1, n do
        local offset = CAT_OFFSETS[math.random(#CAT_OFFSETS)]
        local along = Random(-55, 55)
        local p = Part(fx, "drop", offset + cos(CAT) * along, sin(CAT) * along, Random(-6, 6), Random(-10, 10), Random(0.5, 0.8), Random(5, 8), 0.72, 0.03, 0.05)
        if p then
            p.g = -300
        end
    end
end

Register("feral", "Cat Claw", "DRUID", 103, PieceStyle("feral", {
    files = { "CaseClawBand1", "CaseClawBand2", "CaseClawBand3", "CaseClawBand4" },
    moves = {
        { vx = -60, vy = 30, g = 560 },
        { vx = -20, vy = 50, g = 560, delay = 0.05 },
        { vx = 20, vy = 50, g = 560, delay = 0.1 },
        { vx = 60, vy = 30, g = 560, delay = 0.15 },
    },
    split = 0.32, flyFor = 0.65, fadeFrom = 0.2, fadeFor = 0.3, openFor = 0.95, closeFor = 0.5,
    Build = function(fx, art)
        art.dark = Tex(art, fx.top, "CaseVignette", "BLEND", 0, 0, 0, "OVERLAY", 0)
        art.eyes = Tex(art, fx.top, "CaseEyes", "ADD", 0.85, 1, 0.3, "OVERLAY", 1)
        art.gouge = Tex(art, fx.top, "CaseClawCat", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.rake = Tex(art, fx.top, "CaseClawCatGlow", "ADD", 1, 0.78, 0.3, "OVERLAY", 3)
        art.swipe = Tex(art, fx.top, "CaseSlashArc", "ADD", 1, 0.6, 0.15, "OVERLAY", 4)
    end,
    Enter = function(fx)
        Mood(fx, { 0.05, 0.03, 0.01 }, { 1, 0.8, 0.25 })
    end,
    Split = function(fx)
        fx.shake = 1
        Chips(fx, 5, 0, 0, 30, 100, 50)
    end,
    Join = function(fx)
        SparksAlong(fx, 6, 0, 0, CAT, 110, 1, 0.8, 0.3)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            -- the dark falls, a cat's eyes open in it and blink
            local dark = Clamp01(t / 0.1) * (1 - Clamp01((t - 0.22) / 0.12))
            Put(fx, art.dark, 0, 0, w * 1.05, h * 1.1, dark * 0.75)
            local eyes = Clamp01(t / 0.06) * (1 - Clamp01((t - 0.14) / 0.04))
            if t > 0.09 and t < 0.11 then
                eyes = 0.15
            end
            if eyes > 0 then
                Put(fx, art.eyes, 0, 18, 36, 18, eyes)
            else
                Off(art.eyes)
            end
            -- the swipe: three claws at once, a raking glow, then the gouges bleed until they part
            local age = t - 0.16
            local sweep = -0.3 * (1 - EaseOutCubic(Clamp01(age / 0.06)))
            PutTurned(fx, art.swipe, 0, 0, 180, CAT + sweep, SlashAlpha(age) * 0.8)
            PutTurned(fx, art.rake, 0, 0, 170, CAT, SlashAlpha(age))
            PutTurned(fx, art.gouge, 0, 0, 170, CAT, Clamp01(age / 0.04) * (1 - Clamp01((t - 0.32) / 0.08)))
            if age >= 0 and not fx.flags.raked then
                fx.flags.raked = true
                fx.shake = 1.1
                Bleed(fx, 6)
                Sparks(fx, 6, 0, 0, CAT + pi / 2, 0.8, 80, 180, 1, 0.75, 0.3, 200)
            end
            if age > 0.03 and t < 0.32 and Chance(25, dt) then
                Bleed(fx, 1)
            end
        else
            Off(art.dark)
            Off(art.eyes)
            Off(art.swipe)
            Off(art.rake)
            Off(art.gouge)
        end
        MoveReel(fx, SplitSpeed(fx, 0.32, 150, 400), dt)
        DressCells(fx, 0.06, false, true, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Bear Maul (Guardian druid): the ground shakes, a heavy rake, a smash that cracks the gates; they drop ----------

local BEAR_DUST = { 0.6, 0.5, 0.4 }

local function Dust(fx, x, y, vx, vy, life, size, alpha)
    return Smoke(fx, x, y, vx, vy, life, size, alpha, BEAR_DUST[1], BEAR_DUST[2], BEAR_DUST[3])
end

Register("guardian", "Bear Maul", "DRUID", 104, PieceStyle("guardian", {
    files = { "CaseMaulBand1", "CaseMaulBand2", "CaseMaulBand3" },
    moves = {
        { vx = -30, vy = 10, g = 900 },
        { vx = 0, vy = 5, g = 1000, delay = 0.05 },
        { vx = 30, vy = 10, g = 900, delay = 0.1 },
    },
    split = 0.52, flyFor = 0.55, fadeFrom = 0.25, fadeFor = 0.2, openFor = 1.1, closeFor = 0.6,
    Build = function(fx, art)
        art.gouge = Tex(art, fx.top, "CaseClawBear", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.rake = Tex(art, fx.top, "CaseClawBearGlow", "ADD", 1, 0.62, 0.35, "OVERLAY", 3)
        art.swipe = Tex(art, fx.top, "CaseSlashArc", "ADD", 1, 0.55, 0.25, "OVERLAY", 4)
        art.cracks = Tex(art, fx.top, "CaseCracks", "BLEND", 0.12, 0.08, 0.05, "OVERLAY", 1)
        art.hot = Tex(art, fx.top, "CaseCracks", "ADD", 1, 0.55, 0.25, "OVERLAY", 1)
    end,
    Enter = function(fx)
        Mood(fx, { 0.05, 0.035, 0.02 }, { 0.95, 0.62, 0.3 })
    end,
    Split = function(fx)
        fx.shake = 1.4
        Chips(fx, 6, 0, 0, 30, 90, 70)
    end,
    Join = function(fx)
        fx.shake = 1.6
        for side = -1, 1, 2 do
            Dust(fx, side * 60, -fx.slotHeight / 2 + 10, side * Random(20, 50), Random(5, 20), 0.8, 36, 0.6)
        end
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            -- the ground rumbles first
            if not fx.flags.rumble then
                fx.flags.rumble = true
                fx.shake = 0.7
                for _ = 1, 3 do
                    Dust(fx, Random(-90, 90), -h / 2 + 6, Random(-15, 15), Random(5, 15), 0.7, 30, 0.45)
                end
            end
            -- the rake: four claws
            local age = t - 0.1
            local sweep = 0.3 * (1 - EaseOutCubic(Clamp01(age / 0.08)))
            PutTurned(fx, art.swipe, 0, 0, 260, BEAR + sweep, SlashAlpha(age) * 0.7)
            PutTurned(fx, art.rake, 0, 0, 230, BEAR, SlashAlpha(age))
            local stay = 1 - Clamp01((t - 0.52) / 0.08)
            PutTurned(fx, art.gouge, 0, 0, 230, BEAR, Clamp01(age / 0.04) * stay)
            if age >= 0 and not fx.flags.raked then
                fx.flags.raked = true
                fx.shake = 2.2
                Chips(fx, 5, 0, 0, 50, 130, 60)
                for _ = 1, 3 do
                    Dust(fx, Random(-50, 50), Random(-20, 20), Random(-40, 40), Random(-10, 20), Random(0.6, 0.9), Random(30, 44), 0.5)
                end
            end
            -- the smash: cracks race out from the middle
            local smash = t - 0.34
            if smash >= 0 then
                if not fx.flags.smash then
                    fx.flags.smash = true
                    fx.shake = 2.6
                    Chips(fx, 6, 0, 0, 60, 150, 20)
                    Sparks(fx, 6, 0, 0, pi / 2, pi, 60, 160, 1, 0.65, 0.3, 300)
                end
                local grow = 0.4 + 0.6 * EaseOutCubic(smash / 0.12)
                Put(fx, art.cracks, 0, 0, w * grow, h * grow, 0.85 * stay)
                Put(fx, art.hot, 0, 0, w * grow, h * grow, 0.5 * stay * (1 - Clamp01(smash / 0.3)))
            else
                Off(art.cracks)
                Off(art.hot)
            end
            -- the pieces land: dust where they hit the bottom
            if t > 0.78 and not fx.flags.landed then
                fx.flags.landed = true
                fx.shake = 1.2
                for _ = 1, 4 do
                    Dust(fx, Random(-80, 80), -h / 2 + 6, Random(-30, 30), Random(5, 25), Random(0.6, 0.9), Random(32, 46), 0.55)
                end
            end
        else
            Off(art.swipe)
            Off(art.rake)
            Off(art.gouge)
            Off(art.cracks)
            Off(art.hot)
        end
        MoveReel(fx, SplitSpeed(fx, 0.52, 70, 300), dt)
        DressCells(fx, 0.12, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Bonestorm (Blood death knight): bone shards circle the lock, faster and faster, and grind the gates away -------
-- from the middle out, then fly off past the edges. Closing, they ride the mending edge back in and snap away.

local STORM_BONES = 8
local STORM_ASPECT = 0.7                 -- the storm's height against its width
local STORM_FILL = 0.72                  -- how much of CaseShred's half-size the torn hole surely covers
local STORM_SPIN, STORM_GRIND, STORM_FLING = 0.2, 0.5, 0.92
local STORM_SHUT = 0.52                  -- closing: the gates whole again
local STORM_SNAP = 0.07                  -- closing: the bones closing in on the lock, then gone
local STORM_SPEED = 2600                 -- the bones' top speed along the orbit, a second
local GATE_CHIP = { 0.86, 0.68, 0.42 }

-- How far across the storm reaches (its height STORM_ASPECT of that) once every corner is ground away.
local function StormReach(fx)
    local x, y = fx.slotWidth / 2, fx.slotHeight / 2 / STORM_ASPECT
    return math.sqrt(x * x + y * y) + 12
end

-- The storm now: the bones' orbit and the hole it has ground (both across), and its spin (a second).
local function Storm(fx, art)
    local t, reach = fx.t, art.reach
    if fx.phase == "opening" then
        if t < STORM_SPIN then
            return 24 + 14 * EaseOutCubic(t / STORM_SPIN), 0, 3 + 5 * t / STORM_SPIN
        elseif t < STORM_GRIND then
            local k = (t - STORM_SPIN) / (STORM_GRIND - STORM_SPIN)
            return 38 + 6 * k, 0, 8 + 18 * EaseInCubic(k)
        end
        local k = Clamp01((t - STORM_GRIND) / (STORM_FLING - STORM_GRIND))
        local orbit = 44 + (reach + 26 - 44) * k * k
        return orbit, min(reach, (orbit - 8) * Clamp01((t - STORM_GRIND) / 0.07)), min(26, STORM_SPEED / orbit)
    elseif fx.phase == "open" then
        return reach + 26, reach + 30, 0
    end
    local hole = reach * (1 - EaseInOut(Clamp01(t / STORM_SHUT)))
    return hole + 8, hole, min(22, STORM_SPEED / (hole + 8))
end

-- A point on the storm's orbit `r` across, at angle `a`, and the way along it there.
local function OnOrbit(r, a)
    local x, y = cos(a) * r, sin(a) * r * STORM_ASPECT
    return x, y, atan2(cos(a) * STORM_ASPECT, -sin(a))
end

-- The bones on their orbit: the far side smaller and dimmer, each trailing a streak of blood light
-- as long as it is fast. `fade` dims them all (appearing), `scale` shrinks them (taken into the lock).
local function PlaceBones(fx, art, orbit, omega, fade, scale)
    local streak = min(64, abs(omega) * orbit * 0.045)
    local trail = Clamp01((abs(omega) - 6) / 14) * 0.85
    local grow = (1 + 0.45 * Clamp01((orbit - 44) / 110)) * (scale or 1)
    local time = GetTime()
    for i, seat in ipairs(art.seat) do
        local a = art.phi + seat.angle
        local x, y, heading = OnOrbit(orbit + seat.out, a)
        local far = sin(a)                  -- 1 at the back of the orbit, -1 at the front
        local depth = 1 - 0.14 * far
        local alpha = fade * (0.86 - 0.14 * far)
        PutTurned(fx, art.bones[i], x, y, 22 * seat.size * depth * grow, heading + 0.45 * sin(time * seat.tumble + i), alpha)
        if trail > 0 and streak > 4 then
            local length = streak * depth
            PutTurned(fx, art.trails[i], x - cos(heading) * length * 0.42, y - sin(heading) * length * 0.42, length, heading, trail * alpha)
        else
            Off(art.trails[i])
        end
    end
end

local function HideBones(art)
    for i = 1, STORM_BONES do
        Off(art.bones[i])
        Off(art.trails[i])
    end
end

-- What the storm throws: a spark off a bone, along its way; bits of the gates and bone dust off the edge.
local function StormSpark(fx, art, orbit)
    local seat = art.seat[math.random(STORM_BONES)]
    local x, y, heading = OnOrbit(orbit + seat.out, art.phi + seat.angle)
    local a = heading + Random(-0.35, 0.35)
    local speed = Random(160, 300)
    local p = Part(fx, "spark", x, y, cos(a) * speed, sin(a) * speed, Random(0.2, 0.34), Random(9, 13), 1, 0.16, 0.16)
    if p then
        p.g, p.drag, p.grow = -160, 0.95, -0.5
    end
end

local function StormChip(fx, hole, dust)
    local a = Random(0, pi * 2)
    local x, y, heading = OnOrbit(hole, a)
    local speed = Random(150, 260)
    local vx, vy = cos(heading) * speed + cos(a) * Random(40, 100), sin(heading) * speed + sin(a) * Random(40, 100) + 40
    if dust then
        Smoke(fx, x, y, vx * 0.2, vy * 0.2, Random(0.5, 0.75), Random(20, 28), 0.35, 0.84, 0.78, 0.7)
        return
    end
    local p = Part(fx, "chip", x, y, vx, vy, Random(0.5, 0.8), Random(5, 8), GATE_CHIP[1], GATE_CHIP[2], GATE_CHIP[3])
    if p then
        p.g, p.grow, p.late = -560, 0, true
    end
end

Register("blood", "Bonestorm", "DEATHKNIGHT", 250, HoleStyle("blood", {
    shape = "CaseShred", fill = STORM_FILL, openFor = 1.15, closeFor = 0.8,
    Build = function(fx, art)
        art.core = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.12, 0.15, "OVERLAY", 0)
        art.track = Tex(art, fx.top, "CaseRing", "ADD", 0.9, 0.08, 0.1, "OVERLAY", 0)
        art.edge = Tex(art, fx.top, "CaseShredRim", "BLEND", 0.16, 0.02, 0.03, "OVERLAY", 1)
        art.rim = Tex(art, fx.top, "CaseShredRim", "ADD", 1, 0.16, 0.18, "OVERLAY", 2)
        art.trails, art.bones, art.seat = {}, {}, {}
        for i = 1, STORM_BONES do
            art.trails[i] = Tex(art, fx.top, "CaseSpark", "ADD", 1, 0.1, 0.12, "OVERLAY", 3)
            local shape = (i - 1) % 4
            local bone = Tex(art, fx.top, "CaseBones", "BLEND", nil, nil, nil, "OVERLAY", 4)
            bone:SetTexCoord(shape / 4, (shape + 1) / 4, 0, 1)
            art.bones[i] = bone
            -- each bone's place in the storm: its angle, a little in or out, how big, how it tumbles
            art.seat[i] = { angle = (i - 1) / STORM_BONES * pi * 2 + Random(-0.25, 0.25), out = Random(-5, 5),
                size = Random(0.85, 1.15), tumble = Random(-2.5, 2.5) }
        end
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.3, 0.3, "OVERLAY", 5)
        art.wave = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.14, 0.16, "OVERLAY", 5)
        art.burst = Tex(art, fx.top, "CaseVignette", "ADD", 0.95, 0.08, 0.1, "OVERLAY", 5)
        art.ambient = Tex(art, fx.mid, "CaseVignette", "ADD", 0.7, 0.03, 0.05)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.06, 0.01, 0.015 }, { 1, 0.2, 0.25 }, 0.8)
        K.EnsureMarkerGlow(fx)
        art.reach = StormReach(fx)
        art.phi = Random(0, pi * 2)
        art.flashAt, art.burstAt, art.biteAt = nil, nil, nil
    end,
    Radius = function(fx, art)
        local orbit, hole, omega = Storm(fx, art)
        art.orbit, art.hole, art.omega = orbit, hole, omega
        return hole, hole * STORM_ASPECT
    end,
    Update = function(fx, art, dt, hole)
        local t, flags = fx.t, fx.flags
        local w, h = fx.slotWidth, fx.slotHeight
        local orbit, omega = art.orbit, art.omega
        local opening, closing = fx.phase == "opening", fx.phase == "closing"
        art.phi = art.phi + omega * dt

        -- the bones: summoned at the lock and whirling until they're flung past the edges; closing,
        -- back in on the mending edge, then into the lock
        local bones, scale = 0, 1
        if opening and t < STORM_FLING then
            bones = Clamp01(t / 0.16)
        elseif closing and t < STORM_SHUT + STORM_SNAP then
            bones = Clamp01(t / 0.1)
            if t >= STORM_SHUT then
                local k = (t - STORM_SHUT) / STORM_SNAP
                orbit, scale = orbit * (1 - k), 1 - 0.6 * k
            end
        end
        if bones > 0 then
            PlaceBones(fx, art, orbit, omega, bones, scale)
            local track = 0.3 * Clamp01((omega - 8) / 12) * bones
            if track > 0 then
                Put(fx, art.track, 0, 0, orbit * 2.08, orbit * 2.08 * STORM_ASPECT, track)
            else
                Off(art.track)
            end
        else
            HideBones(art)
            Off(art.track)
        end

        if opening then
            if t < STORM_GRIND then
                -- the storm gathers: blood light at the lock, the gates reddening, sparks where bones scrape
                local k = t / STORM_GRIND
                Put(fx, art.core, 0, 0, 30 + 60 * EaseOutCubic(k), 26 + 44 * EaseOutCubic(k), 0.2 + 0.5 * k + 0.08 * sin(GetTime() * 31))
                fx.shake = max(fx.shake or 0, 0.12 + 0.55 * Clamp01((omega - 8) / 18))
                if t >= STORM_SPIN and Chance(3 + omega * 1.1, dt) then
                    StormSpark(fx, art, orbit)
                end
            else
                Put(fx, art.core, 0, 0, 90, 70, 0.7 * (1 - Clamp01((t - STORM_GRIND) / 0.25)))
                if not flags.bite then
                    -- it bites in: the middle of the gates goes at once
                    flags.bite = true
                    fx.shake = 1.4
                    art.flashAt = GetTime()
                    art.biteAt = art.flashAt
                    Sparks(fx, 12, 0, 0, 0, pi, 130, 280, 1, 0.18, 0.18, 220)
                    Chips(fx, 6, 0, 0, 60, 160, 16)
                end
                if t < STORM_FLING then
                    fx.shake = max(fx.shake or 0, 0.9)
                    if Chance(42, dt) then
                        StormChip(fx, hole)
                    end
                    if Chance(12, dt) then
                        StormChip(fx, hole, true)
                    end
                    if Chance(24, dt) then
                        StormSpark(fx, art, orbit)
                    end
                elseif not flags.fling then
                    -- flung past the edges: a last flare of blood light around the slot
                    flags.fling = true
                    fx.shake = 0.9
                    art.burstAt = GetTime()
                end
            end
            local red = 0.3 * Clamp01(t / STORM_GRIND)
            K.FaceTint(fx, 1, 1 - red, 1 - red)
        elseif closing then
            Off(art.core)
            if hole > 4 and Chance(16, dt) then
                StormChip(fx, hole, true)
            end
            if t >= STORM_SHUT + STORM_SNAP and not flags.snapped then
                -- into the lock, and gone
                flags.snapped = true
                fx.shake = 0.9
                art.flashAt = GetTime()
                Burst(fx, "bone", 5, 0, 0, 80, 170, 0.45, 9, 1, 1, 1)
                Sparks(fx, 6, 0, 0, 0, pi, 70, 150, 1, 0.2, 0.2, 160)
            end
            local red = 0.3 * (1 - Clamp01(t / STORM_SHUT))
            K.FaceTint(fx, 1, 1 - red, 1 - red)
        else
            Off(art.core)
        end

        -- the torn edge: blood light on it, the gates darkened around it
        if hole > 1 and hole < art.reach then
            local across = 2 * hole / STORM_FILL
            Put(fx, art.rim, 0, 0, across, across * STORM_ASPECT, 0.85 + 0.15 * sin(GetTime() * 27))
            Put(fx, art.edge, 0, 0, across * 1.07, across * 1.07 * STORM_ASPECT, 0.85)
        else
            Off(art.rim)
            Off(art.edge)
        end
        Flash(fx, art.flash, art.flashAt, 0.2, 0, 0, 110, 80, 1)
        Ring(fx, art.wave, art.biteAt, 0.35, 0, 0, 40, 190, STORM_ASPECT, 0.75)
        Flash(fx, art.burst, art.burstAt, 0.32, 0, 0, w, h, 0.3)

        -- open: blood light breathing at the slot's edges, the marker in time
        local breath = 0.5 + 0.5 * sin(GetTime() * 2.4)
        if fx.phase == "open" then
            Put(fx, art.ambient, 0, 0, w, h, 0.12 + 0.08 * breath)
        else
            Off(art.ambient)
        end
        if fx.markerGlow then
            fx.markerGlow:SetAlpha(fx.phase == "open" and 0.3 + 0.35 * breath or 0)
        end
        MoveReel(fx, SplitSpeed(fx, STORM_GRIND, 90, 320), dt)
        DressCells(fx, 0.08, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Chaos Bolt (Destruction warlock): a blazing bolt hits the lock; the scorched gates explode, burning bits rain -----

local BOLT_ANGLE = -atan2(30, SLOT_W / 2 + 40)

Register("destruction", "Chaos Bolt", "WARLOCK", 267, PieceStyle("destruction", {
    files = X_PIECES,
    moves = {
        { vx = 0, vy = 270, g = 560 },
        { vx = 300, vy = 90, g = 560 },
        { vx = 0, vy = -130, g = 560 },
        { vx = -300, vy = 90, g = 560 },
    },
    split = 0.34, flyFor = 0.55, fadeFrom = 0.12, fadeFor = 0.3, openFor = 0.95, closeFor = 0.55,
    Build = function(fx, art)
        art.tail = Tex(art, fx.top, "CaseComet", "ADD", 1, 0.42, 0.08, "OVERLAY", 2)
        art.comet = Tex(art, fx.top, "CaseComet", "ADD", 0.7, 0.28, 1, "OVERLAY", 3)
        art.core = Tex(art, fx.top, "CaseGlow", "ADD", 0.9, 0.7, 1, "OVERLAY", 4)
        art.light = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.4, 0.15, "OVERLAY", 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.6, 0.25, "OVERLAY", 5)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.5, 0.15, "OVERLAY", 5)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.06, 0.015, 0.01 }, { 1, 0.5, 0.2 })
        art.flashAt, art.boomAt = nil, nil
    end,
    Split = function(fx, art)
        fx.shake = 2.6
        art.flashAt, art.boomAt = GetTime(), GetTime()
        Off(art.tail)
        Off(art.comet)
        Off(art.core)
        Off(art.light)
        TintPieces(art, 0.55, 0.38, 0.32)
        Sparks(fx, 16, 0, 0, 0, pi, 120, 300, 1, 0.55, 0.15, 250)
        Chips(fx, 6, 0, 0, 60, 160, 20, 0.35, 0.25, 0.2)
        for _ = 1, 5 do
            local a = Random(0, pi * 2)
            Smoke(fx, cos(a) * 15, sin(a) * 10, cos(a) * Random(30, 70), sin(a) * Random(20, 50) + 15, Random(0.8, 1.1), Random(40, 60), 0.75, 0.22, 0.13, 0.16)
        end
        for _ = 1, 6 do
            local p = Part(fx, "ember", Random(-20, 20), Random(-10, 10), Random(-140, 140), Random(60, 200), Random(0.6, 1), Random(4, 7), 1, Random(0.35, 0.6), 0.1)
            if p then
                p.g = -420
            end
        end
    end,
    Join = function(fx, art)
        fx.shake = 0.8
        art.flashAt = GetTime()
        Burst(fx, "sparkle", 6, 0, 0, 30, 70, 0.4, 7, 0.75, 0.35, 1)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" and t < 0.34 then
            local k = EaseInCubic(t / 0.34)
            local x, y = -w / 2 - 40 + (w / 2 + 40) * k, 30 * (1 - k)
            local wobble = 1 + 0.12 * sin(t * 60)
            PutTurned(fx, art.tail, x - 34, y + 7, 150 * wobble, BOLT_ANGLE, 1)
            PutTurned(fx, art.comet, x - 26, y + 5, 120, BOLT_ANGLE, 1)
            Put(fx, art.core, x, y, 40 * wobble, 40 * wobble, 1)
            -- its light on the gates, stronger as it comes
            Put(fx, art.light, x * 0.6, y * 0.6, 160, 110, 0.15 + 0.35 * k)
            if Chance(70, dt) then
                local purple = math.random() < 0.5
                local p = Part(fx, "spark", x - 10, y + Random(-6, 6), Random(-160, -60), Random(-30, 30), Random(0.2, 0.35), Random(9, 12),
                    purple and 0.7 or 1, purple and 0.3 or 0.45, purple and 1 or 0.1)
                if p then
                    p.drag = 0.92
                end
            end
        end
        if fx.phase == "open" and Chance(5, dt) then
            local p = Part(fx, "ember", Random(-w / 2 + 10, w / 2 - 10), h / 2 - GATE_CORNER, Random(-10, 10), Random(-20, 0), Random(0.8, 1.2), Random(4, 6), 1, Random(0.35, 0.55), 0.1)
            if p then
                p.g = -60
            end
        elseif fx.phase == "closing" then
            -- the scorch fades as the pieces fly back
            local k = Clamp01(t / 0.38)
            TintPieces(art, 0.55 + 0.45 * k, 0.38 + 0.62 * k, 0.32 + 0.68 * k)
        end
        Flash(fx, art.flash, art.flashAt, 0.3, 0, 0, 200, 140, 1)
        Ring(fx, art.ring, art.boomAt, 0.4, 0, 0, 40, 320, 0.7)
        MoveReel(fx, SplitSpeed(fx, 0.34, 100, 500), dt)
        DressCells(fx, 0, false, false, 0, fx.phase == "open" and 0.8 or 0.3)
        K.Shake(fx, dt)
    end,
}))

-- --- Lightning Strike (Elemental shaman): the sky darkens, a bolt hits, the cracks glow, the gates blow out -----------

Register("elemental", "Lightning Strike", "SHAMAN", 262, PieceStyle("elemental", {
    files = X_PIECES,
    moves = {
        { vx = 0, vy = 220, g = 300 },
        { vx = 260, vy = 30, g = 300 },
        { vx = 0, vy = -220, g = 0 },
        { vx = -260, vy = 30, g = 300 },
    },
    split = 0.46, flyFor = 0.45, fadeFrom = 0.08, fadeFor = 0.25, openFor = 0.9, closeFor = 0.55,
    Build = function(fx, art)
        art.storm = Tex(art, fx.top, nil, "BLEND", nil, nil, nil, "OVERLAY", 0)
        K.ColorTexture(art.storm, 0.03, 0.05, 0.1, 1)
        art.cracks = Tex(art, fx.top, "CaseCracks", "ADD", 0.5, 0.75, 1, "OVERLAY", 1)
        art.bolt = Tex(art, fx.top, "CaseBolt", "ADD", 0.72, 0.86, 1, "OVERLAY", 2)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 0.8, 0.9, 1, "OVERLAY", 3)
        art.far = Tex(art, fx.mid, "CaseBolt", "ADD", 0.6, 0.75, 1)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.02, 0.03, 0.06 }, { 0.55, 0.75, 1 })
        art.boltX = Random(-24, 24)
        art.nextFlicker = Random(0.6, 1.4)
        art.farAge = nil
    end,
    Split = function(fx, art)
        fx.shake = 1.8
        Off(art.cracks)
        Off(art.storm)
        Sparks(fx, 14, 0, 0, 0, pi, 120, 280, 0.65, 0.85, 1, 120)
        Chips(fx, 5, 0, 0, 60, 140, 20)
    end,
    Join = function(fx)
        Sparks(fx, 6, 0, 0, 0, pi, 40, 100, 0.65, 0.85, 1, 0)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            if t < 0.46 then
                -- the sky darkens, flickers twice, and the bolt strikes at 0.24
                local dark = Clamp01(t / 0.2) * 0.45
                if (t > 0.08 and t < 0.1) or (t > 0.15 and t < 0.17) then
                    dark = 0.1
                end
                Put(fx, art.storm, 0, 0, w, h, dark)
                if t >= 0.24 then
                    if not fx.flags.struck then
                        fx.flags.struck = true
                        fx.shake = 1.4
                        Sparks(fx, 8, art.boltX * 0.5, 0, pi / 2, 1.2, 80, 200, 0.75, 0.9, 1, 300)
                    end
                    local q = EaseOutCubic((t - 0.24) / 0.15)
                    Put(fx, art.cracks, 0, 0, w * (0.4 + 0.6 * q), h * (0.4 + 0.6 * q), q * (0.8 + 0.2 * sin(t * 70)))
                end
                -- the gates blanch in the strike's light
                local lit = t >= 0.24 and 1 - Clamp01((t - 0.24) / 0.2) or 0
                K.FaceTint(fx, 1 - 0.25 * lit, 1 - 0.12 * lit, 1, lit > 0.5)
            end
            local strike = t - 0.24
            if strike >= 0 and strike < 0.32 then
                local flicker = (strike < 0.08 or (strike > 0.14 and strike < 0.2)) and 1 or 0.35
                Put(fx, art.bolt, art.boltX, h / 2 - 38, 34, 136, flicker * (1 - strike / 0.32))
                Put(fx, art.flash, art.boltX * 0.5, 0, 140, 110, (1 - strike / 0.32) * 0.8)
            else
                Off(art.bolt)
                Off(art.flash)
            end
        elseif fx.phase == "open" then
            -- the storm goes on far behind: a faint bolt now and then
            art.nextFlicker = art.nextFlicker - dt
            if art.nextFlicker <= 0 then
                art.nextFlicker = Random(1.2, 2.2)
                art.farAge = 0
                art.farX = Random(-w / 2 + 20, w / 2 - 20)
            end
            if art.farAge then
                art.farAge = art.farAge + dt
                if art.farAge < 0.18 then
                    Put(fx, art.far, art.farX, 10, 22, 90, (art.farAge < 0.05 or art.farAge > 0.1) and 0.3 or 0.1)
                else
                    Off(art.far)
                    art.farAge = nil
                end
            end
        else
            Off(art.far)
        end
        MoveReel(fx, SplitSpeed(fx, 0.46, 110, 400), dt)
        DressCells(fx, 0, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- =============================================================================================================
-- A line across the slot
-- =============================================================================================================

-- --- Plague (Unholy death knight): green slime bubbles up from the bottom and rots the gates away -----------------

Register("unholy", "Plague", "DEATHKNIGHT", 252, WipeStyle("unholy", {
    dir = "up", delay = 0.12, travel = 0.85, back = 0.75, openFor = 1.0, closeFor = 0.8,
    edge = { file = "CaseOozeEdge", r = 0.45, g = 0.95, b = 0.2, thick = 30, tile = 150, scroll = 0.12 },
    -- the slime's edge wobbles as it rises
    Wobble = function(fx, u)
        if u > 0 and u < 1 then
            return u + 0.025 * sin(fx.t * 9)
        end
        return u
    end,
    Build = function(fx, art)
        art.glow = Tex(art, fx.mid, "CaseGlow", "ADD", 0.4, 1, 0.15)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.02, 0.05, 0.01 }, { 0.5, 1, 0.3 })
        Put(fx, art.glow, 0, -fx.slotHeight / 2 + GATE_CORNER, fx.windowWidth * 1.2, 60, 0.2)
    end,
    Update = function(fx, art, dt, u, y)
        local w, h = fx.slotWidth, fx.slotHeight
        -- the gates sicken as the slime climbs them
        local rot = Clamp01(u)
        K.FaceTint(fx, 1 - 0.3 * rot, 1 - 0.05 * rot, 1 - 0.45 * rot)
        if u > 0 and u < 1 and y > -h / 2 + 4 then
            -- bubbles rise from the slime's edge and pop
            if Chance(18, dt) then
                local p = Part(fx, "bubble", Random(-w / 2 + 6, w / 2 - 6), y - Random(0, 8), Random(-5, 5), Random(15, 35), Random(0.35, 0.7), Random(5, 10), 0.55, 1, 0.3, 0.85)
                if p then
                    p.grow = 0.6
                end
            end
            if Chance(5, dt) then
                Smoke(fx, Random(-w / 2 + 10, w / 2 - 10), y, Random(-6, 6), Random(10, 25), Random(0.7, 1), Random(26, 36), 0.25, 0.45, 0.9, 0.25)
            end
            if fx.phase == "closing" and Chance(10, dt) then
                local p = Part(fx, "drop", Random(-w / 2 + 6, w / 2 - 6), y, 0, Random(-30, -10), Random(0.4, 0.6), Random(5, 7), 0.45, 0.9, 0.2)
                if p then
                    p.g = -200
                end
            end
        end
        if fx.phase == "open" and Chance(7, dt) then
            local p = Part(fx, "bubble", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER + 2, Random(-4, 4), Random(12, 26), Random(0.8, 1.4), Random(4, 8), 0.55, 1, 0.3, 0.7)
            if p then
                p.grow = 0.5
            end
        end
        art.glow:SetAlpha(fx.phase == "open" and 0.35 or 0.2)
        MoveReel(fx, 70, dt)
        DressCells(fx, 0, false, false, 1.5, 0)
    end,
}))

-- --- Poison Drip (Assassination rogue): drops eat through the lock, then poison runs down the gates -------------------

local POISON_DROPS = { 0.0, 0.08, 0.16 }

Register("assassination", "Poison Drip", "ROGUE", 259, WipeStyle("assassination", {
    dir = "down", delay = 0.3, travel = 0.7, back = 0.7, openFor = 1.0, closeFor = 0.75,
    edge = { file = "CaseDripEdge", r = 0.72, g = 1, b = 0.18, thick = 40, tile = 170, scroll = 0.04, shift = -8 },
    Build = function(fx, art)
        art.hiss = Tex(art, fx.top, "CaseGlow", "ADD", 0.7, 1, 0.2, "OVERLAY", 1)
    end,
    Enter = function(fx)
        Mood(fx, { 0.03, 0.04, 0.01 }, { 0.75, 1, 0.2 })
    end,
    Update = function(fx, art, dt, u, y)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" and t < 0.4 then
            -- three drops fall on the lock, and it hisses and glows
            for index, at in ipairs(POISON_DROPS) do
                if t >= at and not fx.flags[index] then
                    fx.flags[index] = true
                    local p = Part(fx, "drop", Random(-12, 12), h / 2 - 4, 0, -40, 0.28, 9, 0.72, 1, 0.18)
                    if p then
                        p.g = -500
                    end
                end
                if t >= at + 0.2 and not fx.flags[-index] then
                    fx.flags[-index] = true
                    Smoke(fx, Random(-12, 12), Random(-6, 6), Random(-10, 10), Random(20, 40), Random(0.6, 0.9), Random(26, 36), 0.4, 0.6, 0.95, 0.3)
                    Sparks(fx, 3, 0, 0, pi / 2, 1.2, 30, 80, 0.75, 1, 0.3, 0)
                end
            end
            Put(fx, art.hiss, 0, 0, 70, 50, Clamp01((t - 0.2) / 0.1) * (1 - Clamp01((t - 0.3) / 0.1)) * 0.6)
        else
            Off(art.hiss)
        end
        -- the gates yellow where the poison soaks in
        local soak = Clamp01(u)
        K.FaceTint(fx, 1 - 0.1 * soak, 1, 1 - 0.4 * soak)
        if u > 0 and u < 1 then
            if Chance(14, dt) then
                local p = Part(fx, "drop", Random(-w / 2 + 6, w / 2 - 6), y - Random(4, 18), 0, Random(-40, -10), Random(0.35, 0.6), Random(5, 8), 0.72, 1, 0.18)
                if p then
                    p.g = -260
                end
            end
            if Chance(6, dt) then
                Smoke(fx, Random(-w / 2 + 10, w / 2 - 10), y, Random(-6, 6), Random(15, 30), Random(0.6, 0.9), Random(24, 34), 0.3, 0.6, 0.95, 0.3)
            end
        end
        if fx.phase == "open" and Chance(3, dt) then
            local p = Part(fx, "drop", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), h / 2 - GATE_CORNER, 0, -10, Random(0.6, 0.9), Random(5, 7), 0.72, 1, 0.18)
            if p then
                p.g = -160
            end
        end
        MoveReel(fx, fx.phase == "opening" and 80 * Clamp01(u * 2) or 80, dt)
        DressCells(fx, 0, false, false, 0, 0)
    end,
}))

-- --- Sigil Flames (Vengeance demon hunter): a sigil burns itself into the floor, and fel fire roars up from it ----------

local FLAME_COLUMNS = { -84, -42, 0, 42, 84 }

Register("vengeance", "Sigil Flames", "DEMONHUNTER", 581, WipeStyle("vengeance", {
    dir = "up", delay = 0.36, travel = 0.42, ease = EaseOutCubic, back = 0.7, openFor = 0.9, closeFor = 0.8,
    edge = { file = "CaseFelEdge", thick = 18, tile = 144, scroll = 0.5 },
    Build = function(fx, art)
        art.halo = Tex(art, fx.top, "CaseSigil", "ADD", 0.72, 0.45, 1, "OVERLAY", 1)
        art.sigil = Tex(art, fx.top, "CaseSigil", "ADD", 0.5, 1, 0.3, "OVERLAY", 2)
        art.flare = Tex(art, fx.top, "CaseGlow", "ADD", 0.55, 1, 0.3, "OVERLAY", 3)
        art.columns = {}
        for index in ipairs(FLAME_COLUMNS) do
            art.columns[index] = Tex(art, fx.top, "CaseFlameColumn", "ADD", 0.45, 1, 0.25, "OVERLAY", 4)
        end
        art.floor = Tex(art, fx.mid, "CaseSigil", "ADD", 0.5, 1, 0.3)
    end,
    Enter = function(fx)
        Mood(fx, { 0.02, 0.04, 0.016 }, { 0.55, 1, 0.29 }, 0.85)
    end,
    Update = function(fx, art, dt, u, y)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local base = -h / 2 + 16
        if fx.phase == "opening" then
            -- the sigil draws itself on the floor, flares, and erupts
            local draw = EaseOutCubic(t / 0.26)
            local flare = t > 0.26 and max(0, 1 - (t - 0.26) / 0.3) or 0
            local spread = 0.6 + 0.4 * draw
            Put(fx, art.sigil, 0, base, w * 0.9 * spread, 32 * spread, draw * (0.7 + 0.3 * sin(t * 30)) + flare * 0.3)
            Put(fx, art.halo, 0, base, w * 0.98, 38, draw * 0.35 + flare * 0.4)
            Put(fx, art.flare, 0, base, w * (0.6 + 0.6 * flare), 50, flare)
            if t >= 0.34 and not fx.flags.erupt then
                fx.flags.erupt = true
                fx.shake = 1.5
                Sparks(fx, 10, 0, base, pi / 2, 0.5, 150, 300, 0.55, 1, 0.3, 200)
            end
            for index, column in ipairs(art.columns) do
                local age = t - 0.34 - (index % 3) * 0.025
                if age > 0 and age < 0.5 then
                    local height = 150 * EaseOutCubic(age / 0.15) * (1 - Clamp01((age - 0.25) / 0.25))
                    local flicker = 0.85 + 0.15 * sin(t * 40 + index * 2)
                    Put(fx, column, FLAME_COLUMNS[index], base + height / 2, 28 * flicker, max(1, height), 0.9)
                else
                    Off(column)
                end
            end
            -- the gates catch the green light from below
            K.FaceTint(fx, 1 - 0.3 * flare, 1, 1 - 0.35 * flare)
            Off(art.floor)
        else
            Off(art.sigil)
            Off(art.halo)
            Off(art.flare)
            for _, column in ipairs(art.columns) do
                Off(column)
            end
            -- the sigil stays, faint, below the reel; soul fragments drift up from it
            local faint = fx.phase == "open" and 0.3 + 0.1 * sin(GetTime() * 3) or 0.3 * (1 - Clamp01(t / 0.3))
            Put(fx, art.floor, 0, base, w * 0.86, 30, faint)
            if fx.phase == "open" and Chance(3, dt) then
                local p = Part(fx, "soul", Random(-fx.windowWidth / 2 + 10, fx.windowWidth / 2 - 10), base, Random(-6, 6), Random(18, 32), Random(1.1, 1.6), Random(9, 12), 0.75, 0.5, 1, 0.7)
                if p then
                    p.grow = 0.2
                end
            end
        end
        if u > 0 and u < 1 then
            for _ = 1, 2 do
                if Chance(fx.phase == "closing" and 12 or 30, dt) then
                    local up = fx.phase ~= "closing"
                    local p = Part(fx, "ember", Random(-w / 2 + 2, w / 2 - 2), y, Random(-15, 15), up and Random(120, 220) or Random(-60, -20), Random(0.4, 0.8), Random(3, 5), 0.49, 1, 0.23)
                    if p then
                        p.g = up and -150 or -60
                        p.grow = -0.3
                    end
                end
            end
        end
        MoveReel(fx, 100, dt)
        DressCells(fx, 0, false, false, 0, fx.phase == "open" and 1.0 or 0.4)
        K.Shake(fx, dt)
    end,
}))

-- --- Wake of Ashes (Retribution paladin): a hammer comes down, a golden wave rises, the gates burn to ash ---------------

-- The hammer swung down onto the slot's floor: turned by `swing` (0: upright, head down), its grip
-- held still above where the head lands.
local function Hammer(fx, texture, swing, size, alpha)
    local h = fx.slotHeight
    local hitY = -h / 2 + 14
    local gripX, gripY = 0, hitY + 0.72 * size
    local r = pi + swing
    -- the grip (the art's foot, 0.45 of its size below its centre) stays put as it turns
    local cx = gripX - 0.45 * size * sin(r)
    local cy = gripY + 0.45 * size * cos(r)
    texture:SetRotation(r)
    Put(fx, texture, cx, cy, size, size, alpha)
end

Register("retribution", "Wake of Ashes", "PALADIN", 70, WipeStyle("retribution", {
    dir = "up", delay = 0.3, travel = 0.5, ease = EaseOutCubic, back = 0.65, openFor = 0.95, closeFor = 0.7,
    edge = { file = "CaseOozeEdge", r = 1, g = 0.55, b = 0.15, blend = "ADD", thick = 16, tile = 150, scroll = 0.3 },
    Build = function(fx, art)
        art.hammer = Tex(art, fx.top, "CaseHammer", "BLEND", nil, nil, nil, "OVERLAY", 3)
        art.wave = Tex(art, fx.top, "CaseWave", "ADD", 1, 0.8, 0.35, "OVERLAY", 2)
        art.cracks = Tex(art, fx.top, "CaseCracks", "ADD", 1, 0.78, 0.35, "OVERLAY", 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.85, 0.45, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.06, 0.045, 0.02 }, { 1, 0.85, 0.4 })
        art.hitAt = nil
    end,
    Update = function(fx, art, dt, u, y)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local floor = -h / 2 + 14
        if fx.phase == "opening" and t < 0.42 then
            -- the hammer swings down, strikes, and lifts away
            if t < 0.2 then
                Hammer(fx, art.hammer, -1.1 * (1 - EaseInCubic(t / 0.2)), 80, Clamp01(t / 0.05))
            else
                if not fx.flags.struck then
                    fx.flags.struck = true
                    fx.shake = 2.2
                    art.hitAt = GetTime()
                    Sparks(fx, 14, 0, floor, pi / 2, 1.1, 120, 280, 1, 0.85, 0.45, 350)
                    for _ = 1, 3 do
                        Smoke(fx, Random(-40, 40), floor, Random(-40, 40), Random(10, 30), Random(0.6, 0.9), Random(30, 42), 0.5, 0.55, 0.5, 0.42)
                    end
                end
                Hammer(fx, art.hammer, -0.12 * EaseOutCubic((t - 0.24) / 0.18), 80, 1 - Clamp01((t - 0.26) / 0.14))
            end
        else
            Off(art.hammer)
        end
        local hit = Since(art.hitAt, 0.7)
        if hit > 0 then
            Put(fx, art.cracks, 0, floor + 6, 180 * (1.1 - 0.1 * hit), 70, hit)
        else
            Off(art.cracks)
        end
        Flash(fx, art.flash, art.hitAt, 0.25, 0, floor, 160, 80, 0.9)
        -- the gates char and grey ahead of the wave
        local ash = Clamp01(u)
        K.FaceTint(fx, 1 - 0.45 * ash, 1 - 0.5 * ash, 1 - 0.55 * ash, ash > 0.6)
        if u > 0 and u < 1 and fx.phase == "opening" then
            Put(fx, art.wave, 0, y + 10, w * 1.25, 52, 0.95)
            for _ = 1, 2 do
                if Chance(24, dt) then
                    local p = Part(fx, "chip", Random(-w / 2 + 4, w / 2 - 4), y + Random(0, 8), Random(-20, 20), Random(60, 140), Random(0.5, 0.9), Random(4, 6), 0.32, 0.3, 0.27)
                    if p then
                        p.g = -40
                    end
                end
                if Chance(12, dt) then
                    Part(fx, "spark", Random(-w / 2 + 4, w / 2 - 4), y, Random(-10, 10), Random(60, 130), Random(0.4, 0.7), Random(9, 12), 1, 0.8, 0.35)
                end
            end
        else
            Off(art.wave)
        end
        if fx.phase == "closing" and u > 0 and u < 1 and Chance(16, dt) then
            local p = Part(fx, "chip", Random(-w / 2 + 4, w / 2 - 4), y + Random(0, 20), Random(-8, 8), Random(-30, -10), Random(0.6, 0.9), Random(4, 6), 0.32, 0.3, 0.27)
            if p then
                p.g = -60
            end
        end
        if fx.phase == "open" then
            if Chance(4, dt) then
                local p = Part(fx, "chip", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), h / 2 - GATE_CORNER, Random(-6, 6), Random(-14, -6), Random(1.4, 2), Random(3, 5), 0.32, 0.3, 0.27, 0.8)
                if p then
                    p.spin = Random(-2, 2)
                end
            end
            if Chance(5, dt) then
                Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-4, 4), Random(15, 30), Random(0.8, 1.2), Random(4, 6), 1, 0.85, 0.45, 0.8)
            end
        end
        MoveReel(fx, 100, dt)
        DressCells(fx, 0.06, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Keg Tap (Brewmaster monk): the keg rattles, the cork shoots out, the lid blows, and ale washes the gates down -------

local FOAM = { 1, 0.97, 0.9 }

local function Foam(fx, x, y, vx, vy, life, size, alpha)
    local p = Part(fx, "foam", x, y, vx, vy, life, size, FOAM[1], FOAM[2], FOAM[3], alpha)
    if p then
        p.drag, p.grow = 0.96, 0.3
    end
    return p
end

Register("brewmaster", "Keg Tap", "MONK", 268, WipeStyle("brewmaster", {
    dir = "down", delay = 0.46, travel = 0.5, back = 0.45, openFor = 1.05, closeFor = 0.95,
    edge = { file = "CaseBeerEdge", thick = 34, tile = 160, scroll = 0.15, shift = 3.4 },
    Build = function(fx, art)
        art.lid = Tex(art, fx.top, "CaseKeg", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.cork = Tex(art, fx.top, "CaseCork", "BLEND", nil, nil, nil, "OVERLAY", 3)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.07, 0.04, 0.01 }, { 1, 0.78, 0.3 })
        art.lidX, art.lidY, art.lidVY, art.lidSpin = 0, 0, 0, 0
        art.corkX, art.corkY, art.corkVY, art.corkSpin = 0, -7, 0, 0
    end,
    Update = function(fx, art, dt, u, y)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            if t < 0.4 then
                -- the keg rattles and swells, foam seeping round its rim
                local k = Clamp01(t / 0.4)
                local jolt = 3 * k
                local swell = 56 * (1 + 0.05 * sin(t * 40) * k)
                local x, y0 = Random(-jolt, jolt), Random(-jolt, jolt)
                Put(fx, art.lid, x, y0, swell, swell, 1)
                if Chance(25 * k, dt) then
                    local a = Random(0, pi * 2)
                    Foam(fx, x + cos(a) * 28, y0 + sin(a) * 28, cos(a) * 20, sin(a) * 20, Random(0.4, 0.6), Random(8, 12), 0.9)
                end
                if t < 0.32 then
                    Put(fx, art.cork, x, y0 - 7, 11, 11, 1)
                end
            else
                if not fx.flags.popped then
                    fx.flags.popped = true
                    art.lidX, art.lidY, art.lidVY, art.lidSpin = 0, 0, 260, 0
                    fx.shake = 1
                    for _ = 1, 10 do
                        local a = Random(0.3, pi - 0.3)
                        local p = Foam(fx, cos(a) * 12, sin(a) * 6, cos(a) * Random(40, 110), sin(a) * Random(60, 140), Random(0.6, 0.9), Random(14, 24), 0.95)
                        if p then
                            p.g = -260
                        end
                    end
                end
                -- the lid flies off, turning over
                art.lidVY = art.lidVY - 600 * dt
                art.lidY = art.lidY + art.lidVY * dt
                art.lidX = art.lidX + 40 * dt
                art.lidSpin = art.lidSpin + dt * 12
                Put(fx, art.lid, art.lidX, art.lidY, 56 * (abs(cos(art.lidSpin)) + 0.1), 56, 1)
            end
            -- the cork goes first, with a spurt of foam
            if t >= 0.32 then
                if not fx.flags.cork then
                    fx.flags.cork = true
                    art.corkX, art.corkY, art.corkVY, art.corkSpin = 0, -7, 330, 0
                    fx.shake = 0.6
                    for _ = 1, 4 do
                        Foam(fx, Random(-4, 4), -4, Random(-25, 25), Random(60, 120), Random(0.4, 0.6), Random(10, 14), 0.9)
                    end
                end
                art.corkVY = art.corkVY - 700 * dt
                art.corkY = art.corkY + art.corkVY * dt
                art.corkX = art.corkX - 30 * dt
                art.corkSpin = art.corkSpin + dt * 20
                Put(fx, art.cork, art.corkX, art.corkY, 11 * (abs(cos(art.corkSpin)) + 0.15), 11, 1)
            end
        elseif fx.phase == "open" then
            Off(art.lid)
            Off(art.cork)
            if Chance(7, dt) then
                local p = Part(fx, "bubble", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER + 2, Random(-4, 4), Random(14, 30), Random(0.8, 1.3), Random(4, 7), 1, 0.82, 0.38, 0.75)
                if p then
                    p.grow = 0.4
                end
            end
            if Chance(1.5, dt) then
                local p = Foam(fx, Random(-fx.windowWidth / 2 + 10, fx.windowWidth / 2 - 10), h / 2 - GATE_CORNER, 0, -10, Random(0.8, 1.2), Random(8, 12), 0.8)
                if p then
                    p.g = -120
                end
            end
        else
            -- the flood drains, the lid drops back on, and the cork after it
            if t > 0.45 then
                local k = Clamp01((t - 0.45) / 0.3)
                Put(fx, art.lid, 0, (1 - EaseOutBounce(k)) * (h / 2 + 30), 56, 56, 1)
                if k >= 1 and not fx.flags.landed then
                    fx.flags.landed = true
                    fx.shake = 0.7
                    Foam(fx, 0, -10, 0, 20, 0.5, 18, 0.7)
                end
            else
                Off(art.lid)
            end
            if t > 0.72 then
                local k = Clamp01((t - 0.72) / 0.16)
                Put(fx, art.cork, 0, -7 + (1 - EaseOutBounce(k)) * 50, 11, 11, 1)
            else
                Off(art.cork)
            end
        end
        if u > 0 and u < 1 then
            if Chance(16, dt) then
                Foam(fx, Random(-w / 2 + 6, w / 2 - 6), y - Random(0, 6), Random(-12, 12), Random(-10, 10), Random(0.4, 0.7), Random(10, 16), 0.8)
            end
            if Chance(10, dt) then
                local p = Part(fx, "bubble", Random(-w / 2 + 6, w / 2 - 6), y + Random(4, 26), Random(-3, 3), Random(10, 25), Random(0.4, 0.7), Random(3, 5), 1, 0.82, 0.38, 0.8)
                if p then
                    p.grow = 0.3
                end
            end
        end
        MoveReel(fx, 90, dt)
        DressCells(fx, 0.05, false, true, 2, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Sands of Time (Augmentation evoker): a clock spins backwards, the gates turn to sand and pour away ----------------

local SAND = { { 0.95, 0.8, 0.5 }, { 0.82, 0.62, 0.32 } }

Register("augmentation", "Sands of Time", "EVOKER", 1473, WipeStyle("augmentation", {
    dir = "down", delay = 0.46, travel = 0.6, ease = Smooth, back = 0.55, backDelay = 0.22, openFor = 1.1, closeFor = 0.85,
    edge = { file = "CaseOozeEdge", r = 0.92, g = 0.78, b = 0.48, thick = 12, tile = 120, scroll = 0.02, flip = true },
    Build = function(fx, art)
        art.dial = Tex(art, fx.top, "CaseClock", "ADD", 1, 0.8, 0.45, "OVERLAY", 1)
        art.minute = Tex(art, fx.top, "CaseClockHand", "ADD", 1, 0.88, 0.6, "OVERLAY", 2)
        art.hour = Tex(art, fx.top, "CaseClockHand", "ADD", 1, 0.88, 0.6, "OVERLAY", 2)
        art.glow = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.8, 0.45, "OVERLAY", 3)
        art.glass = Tex(art, fx.top, "CaseHourglass", "BLEND", nil, nil, nil, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.04, 0.02 }, { 0.95, 0.8, 0.45 })
        K.EnsureGhosts(fx)
        art.minuteAngle, art.hourAngle = 0, 0
    end,
    Update = function(fx, art, dt, u, y)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local speed, show, turning = 60, 0, 0
        if fx.phase == "opening" then
            show = Clamp01(t / 0.1) * (1 - Clamp01((t - 0.6) / 0.25))
            turning = -1
            art.glass:SetRotation(pi * EaseInOut((t - 0.1) / 0.3))
            -- the gates dry to sand before they crumble
            local dry = Clamp01((t - 0.15) / 0.3)
            K.FaceTint(fx, 1, 1 - 0.1 * dry, 1 - 0.35 * dry, dry > 0.5)
            -- time runs backwards while the gates crumble, then the reel turns forward again
            if t < 0.46 then
                speed = 0
            else
                speed = -220 * (1 - Clamp01((t - 0.46) / 0.6))
            end
        elseif fx.phase == "open" then
            speed = 60 * EaseOutCubic(t / 0.6)
            if Chance(5, dt) then
                local c = SAND[math.random(2)]
                local p = Part(fx, "grain", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), h / 2 - GATE_CORNER, 0, -20, Random(0.8, 1.1), Random(2, 3), c[1], c[2], c[3], 0.9)
                if p then
                    p.g, p.grow = -60, 0
                end
            end
        else
            -- the hourglass turns back, the clock runs forward, and the sand builds the gates up again
            show = sin(pi * Clamp01(t / 0.75))
            turning = 1
            art.glass:SetRotation(pi * (1 - EaseInOut(t / 0.4)))
            local dry = Clamp01(u)
            K.FaceTint(fx, 1, 1 - 0.1 * dry, 1 - 0.35 * dry, dry > 0.5)
            speed = 60 * (1 - Clamp01(t / 0.3))
        end
        art.minuteAngle = art.minuteAngle + turning * dt * 14
        art.hourAngle = art.hourAngle + turning * dt * 2
        if show > 0 then
            art.dial:SetRotation(art.hourAngle * 0.1)
            Put(fx, art.dial, 0, 0, 114, 114, show * 0.7)
            PutTurned(fx, art.minute, 0, 0, 92, art.minuteAngle, show)
            PutTurned(fx, art.hour, 0, 0, 62, art.hourAngle, show)
            Put(fx, art.glow, 0, 0, 90, 90, show * 0.5)
            Put(fx, art.glass, 0, 0, 46, 46, show)
        else
            Off(art.dial)
            Off(art.minute)
            Off(art.hour)
            Off(art.glow)
            Off(art.glass)
        end
        if u > 0 and u < 1 then
            for _ = 1, 3 do
                if Chance(24, dt) then
                    local c = SAND[math.random(2)]
                    local p = Part(fx, "grain", Random(-w / 2 + 4, w / 2 - 4), y - Random(0, 5), Random(-10, 10), Random(-50, -10), Random(0.4, 0.6), Random(2, 3.5), c[1], c[2], c[3], 1)
                    if p then
                        p.g, p.grow = -380, 0
                    end
                end
            end
            if Chance(5, dt) then
                Smoke(fx, Random(-w / 2 + 10, w / 2 - 10), y, Random(-8, 8), Random(-10, 5), Random(0.6, 0.9), Random(26, 36), 0.3, 0.9, 0.75, 0.5)
            end
        end
        MoveReel(fx, speed, dt)
        DressCells(fx, 0, true, false, 0, 0)
    end,
}))

-- --- Tidal Wave (Restoration shaman): a teal wave sweeps across and washes the gates off ------------------------------

Register("restoshaman", "Tidal Wave", "SHAMAN", 264, WipeStyle("restoshaman", {
    dir = "right", delay = 0.05, travel = 0.75, back = 0.7, openFor = 0.85, closeFor = 0.75,
    edge = { file = "CaseWaveEdgeV", r = 0.5, g = 0.95, b = 1, thick = 34, tile = 140, scroll = 0.6 },
    Enter = function(fx)
        Mood(fx, { 0.01, 0.04, 0.05 }, { 0.4, 0.9, 1 })
    end,
    Update = function(fx, art, dt, u, x)
        local w, h = fx.slotWidth, fx.slotHeight
        x = x - w / 2
        if u > 0 and u < 1 then
            -- spray off the crest
            for _ = 1, 2 do
                if Chance(16, dt) then
                    local back = fx.phase == "closing" and -1 or 1
                    local p = Part(fx, "drop", x + Random(0, 8) * back, Random(-h / 2 + 6, h / 2 - 6), back * Random(40, 120), Random(30, 100), Random(0.4, 0.7), Random(5, 8), 0.6, 0.95, 1, 0.9)
                    if p then
                        p.g = -380
                    end
                end
            end
            if Chance(10, dt) then
                local p = Part(fx, "foam", x, Random(-h / 2 + 10, h / 2 - 10), Random(10, 40), Random(-10, 10), Random(0.4, 0.7), Random(12, 18), 0.88, 1, 1, 0.8)
                if p then
                    p.drag, p.grow = 0.95, 0.3
                end
            end
        end
        if fx.phase == "open" and Chance(7, dt) then
            local p = Part(fx, "bubble", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER + 2, Random(-4, 4), Random(14, 28), Random(0.9, 1.4), Random(4, 8), 0.6, 0.95, 1, 0.75)
            if p then
                p.grow = 0.4
            end
        end
        MoveReel(fx, 70, dt)
        DressCells(fx, 0, false, false, 2.5, 0)
    end,
}))

-- --- Dragon Breath (Devastation evoker): a breath of roiling red and blue fire sweeps across, and the gates melt ---------

-- A layer of rolling fire in the breath's cone: the fire scrolls out of the mouth through its mask.
local function FireLayer(fx, texture, mask, x, w, h, alpha, scroll)
    texture:SetPoint("CENTER", fx, "CENTER", x, 0)
    texture:SetSize(w, h)
    mask:SetPoint("CENTER", fx, "CENTER", x, 0)
    mask:SetSize(w, h)
    texture:SetTexCoord(scroll, scroll + w / 90, scroll * 0.3, scroll * 0.3 + h / 120)
    texture:SetAlpha(alpha)
    Show(texture)
end

Register("devastation", "Dragon Breath", "EVOKER", 1467, WipeStyle("devastation", {
    dir = "right", delay = 0.22, travel = 0.6, back = 0.65, openFor = 0.9, closeFor = 0.75,
    edge = { file = "CaseFlameEdgeV", r = 1, g = 0.55, b = 0.22, thick = 26, tile = 110, scroll = 0.8 },
    Build = function(fx, art)
        for _, key in ipairs({ "outer", "inner" }) do
            local texture = Tex(art, fx.top, nil, "ADD", 1, 1, 1, "OVERLAY", key == "outer" and 2 or 3)
            texture:SetTexture(MEDIA .. "CaseFireNoise", "REPEAT", "REPEAT")
            local mask = fx.top:CreateMaskTexture()
            mask:SetTexture(MEDIA .. "CaseConeMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            texture:AddMaskTexture(mask)
            art[key], art[key .. "Mask"] = texture, mask
        end
        art.outer:SetVertexColor(1, 0.4, 0.08)
        art.inner:SetVertexColor(0.45, 0.72, 1)
        art.mouth = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.6, 0.35, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.02, 0.02 }, { 1, 0.5, 0.25 })
        art.fire = 0
    end,
    Update = function(fx, art, dt, u, x)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local left = -w / 2
        x = x - w / 2
        art.fire = (art.fire - dt * 1.8) % 1
        if fx.phase == "opening" then
            if t < 0.22 then
                -- the breath drawn in: embers gather at the left edge
                Put(fx, art.mouth, left + 6, 0, 30 + 60 * t / 0.22, 30 + 60 * t / 0.22, t / 0.22)
                if Chance(40, dt) then
                    local a = Random(-1.2, 1.2)
                    local p = Part(fx, "ember", left + cos(a) * 70, sin(a) * 50, -cos(a) * 250, -sin(a) * 180, 0.25, Random(4, 6), math.random() < 0.5 and 1 or 0.45, 0.5, math.random() < 0.5 and 0.2 or 1)
                    if p then
                        p.grow = -0.5
                    end
                end
            else
                -- the breath: roiling fire from the left edge out past the burning line
                local reach = max(40, x - left + 50)
                local fade = 1 - Clamp01((t - 0.75) / 0.15)
                local flicker = 0.9 + 0.1 * sin(t * 40)
                FireLayer(fx, art.outer, art.outerMask, left + reach / 2, reach, h * 1.25 * flicker, 0.95 * fade, art.fire)
                FireLayer(fx, art.inner, art.innerMask, left + reach * 0.42, reach * 0.85, h * 0.75 * flicker, 0.9 * fade, art.fire * 1.6)
                art.mouth:SetAlpha(1 - Clamp01((t - 0.6) / 0.2))
            end
        else
            Off(art.outer)
            Off(art.inner)
            Off(art.mouth)
        end
        -- the gates glow with heat as the fire comes
        local heat = Clamp01(u * 1.3)
        K.FaceTint(fx, 1, 1 - 0.35 * heat, 1 - 0.6 * heat)
        if u > 0 and u < 1 then
            for _ = 1, 2 do
                if Chance(24, dt) then
                    local blue = math.random() < 0.4
                    local p = Part(fx, "spark", x + Random(-4, 6), Random(-h / 2 + 4, h / 2 - 4), Random(40, 110), Random(-20, 40), Random(0.3, 0.6), Random(9, 13),
                        blue and 0.45 or 1, blue and 0.7 or 0.45, blue and 1 or 0.15)
                    if p then
                        p.g = -60
                    end
                end
            end
            -- the melting edge drips
            if Chance(10, dt) then
                local p = Part(fx, "drop", x + 4, Random(-h / 2 + 10, h / 2 - 10), Random(0, 10), 0, Random(0.4, 0.7), Random(5, 7), 1, 0.55, 0.15)
                if p then
                    p.g = -260
                end
            end
        end
        if fx.phase == "open" and Chance(10, dt) then
            local blue = math.random() < 0.4
            Part(fx, "ember", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-6, 6), Random(25, 50), Random(0.8, 1.3), Random(4, 6), blue and 0.45 or 1, blue and 0.7 or 0.45, blue and 1 or 0.15)
        end
        MoveReel(fx, 100, dt)
        DressCells(fx, 0, false, false, 0, fx.phase == "open" and 1.0 or 0.4)
    end,
}))

-- =============================================================================================================
-- A hole that grows
-- =============================================================================================================

-- A ring around the hole: `scale` is the ring's size against the hole's (the art's margin).
local function Rim(fx, texture, rx, ry, scale, alpha)
    if rx > 0.5 and alpha > 0 then
        Put(fx, texture, 0, 0, 2 * rx * scale, 2 * ry * scale, alpha)
    else
        Off(texture)
    end
end

-- --- Void Maw (Devourer demon hunter): a toothed maw opens in the middle and pulls the gates in; it bites shut --------

Register("devourer", "Void Maw", "DEMONHUNTER", 1480, HoleStyle("devourer", {
    openFor = 0.65, closeFor = 0.5,
    Build = function(fx, art)
        art.core = Tex(art, fx.window, "CaseGlow", "ADD", 0.55, 0.25, 0.95, "BORDER", 1)
        art.maw = Tex(art, fx.top, "CaseMaw", "ADD", 0.62, 0.36, 1, "OVERLAY", 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 0.8, 0.6, 1, "OVERLAY", 2)
    end,
    Masked = function(art)
        return { art.core }
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.04, 0.01, 0.07 }, { 0.72, 0.45, 1 }, 0.6)
        Put(fx, art.core, 0, 0, 120, 120, 0.6)
        art.bitAt = nil
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * EaseOutBack(t / 0.6, 1.0)
        elseif fx.phase == "open" then
            return fx.rmax + 20
        end
        return fx.rmax * (1 - EaseInCubic(t / 0.3))
    end,
    Update = function(fx, art, dt, r)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        -- the gates darken toward the void as it opens
        local pull = Clamp01(r / fx.rmax)
        K.FaceTint(fx, 1 - 0.35 * pull, 1 - 0.45 * pull, 1 - 0.15 * pull)
        if r < fx.rmax then
            art.maw:SetRotation(-GetTime() * 1.6)
            Rim(fx, art.maw, r, r, 1 / 0.9, 1)
            -- bits of the gates are drawn in, spiralling
            if Chance(40, dt) then
                local a = Random(0, pi * 2)
                local d = r + Random(10, 40)
                local p = Part(fx, "chip", cos(a) * d, sin(a) * d * 0.7, -cos(a) * 120 - sin(a) * 90, -sin(a) * 90 + cos(a) * 70, Random(0.25, 0.4), Random(3, 5), 0.86, 0.68, 0.42, 0.9)
                if p then
                    p.grow = -0.5
                end
            end
        else
            Off(art.maw)
        end
        -- the maw breathes while it's open
        art.core:SetAlpha(0.45 + 0.2 * sin(GetTime() * 2.5))
        if fx.phase == "open" and Chance(8, dt) then
            local a = Random(0, pi * 2)
            Part(fx, "sparkle", cos(a) * w * 0.45, sin(a) * h * 0.35, -cos(a) * 40, -sin(a) * 30, Random(0.6, 0.9), Random(4, 6), 0.75, 0.5, 1)
        end
        if fx.phase == "closing" and t >= 0.3 and not fx.flags.bit then
            fx.flags.bit = true
            fx.shake = 1.6
            art.bitAt = GetTime()
            Sparks(fx, 8, 0, 0, 0, pi, 60, 140, 0.75, 0.5, 1, 0)
        end
        Flash(fx, art.flash, art.bitAt, 0.2, 0, 0, 60, 60, 1)
        MoveReel(fx, fx.phase == "closing" and 60 * (1 - Clamp01(t / 0.3)) or 60, dt)
        DressCells(fx, 0.12, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Void Rift (Shadow priest): a rift tears open, tendrils grip its edges and pull it wide -------------------------

local TENDRILS = { { 1, 22 }, { 1, -18 }, { -1, 16 }, { -1, -24 } } -- side, height

Register("shadow", "Void Rift", "PRIEST", 258, HoleStyle("shadow", {
    openFor = 0.85, closeFor = 0.55,
    Build = function(fx, art)
        art.rim = Tex(art, fx.top, "CaseRing", "ADD", 0.6, 0.3, 0.92, "OVERLAY", 1)
        art.tendrils = {}
        for index, tendril in ipairs(TENDRILS) do
            local texture = Tex(art, fx.top, "CaseTendril", "ADD", 0.55, 0.25, 0.85, "OVERLAY", 2)
            Quarter(texture, tendril[1] > 0)
            art.tendrils[index] = texture
        end
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 0.7, 0.4, 1, "OVERLAY", 3)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.03, 0, 0.05 }, { 0.65, 0.35, 1 }, 0.6)
        art.shutAt = nil
    end,
    Radius = function(fx)
        local t = fx.t
        local rmax = fx.rmax
        if fx.phase == "opening" then
            -- a slit first, then it's pulled wide
            local ry = rmax * 0.9 * EaseOutCubic(t / 0.3) + rmax * 0.3 * EaseInOut((t - 0.3) / 0.5)
            local rx = 4 + (rmax * 1.25) * EaseInOut((t - 0.32) / 0.5)
            return rx, ry
        elseif fx.phase == "open" then
            return rmax * 1.3, rmax * 1.3
        end
        local rx = 4 + rmax * 1.25 * (1 - EaseInOut(t / 0.3))
        local ry = rmax * 1.2 * (1 - EaseInCubic((t - 0.3) / 0.15))
        return rx, ry
    end,
    Update = function(fx, art, dt, rx, ry)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local tearing = fx.phase ~= "open" and rx < fx.rmax * 1.2
        local dark = Clamp01(ry / fx.rmax)
        K.FaceTint(fx, 1 - 0.3 * dark, 1 - 0.4 * dark, 1 - 0.2 * dark)
        Rim(fx, art.rim, rx, ry, 1 / 0.965, tearing and 1 or 0)
        for index, tendril in ipairs(TENDRILS) do
            local texture = art.tendrils[index]
            local reach = 0
            if fx.phase == "opening" then
                reach = EaseOutCubic((t - 0.12) / 0.2) * (1 - Clamp01((t - 0.62) / 0.2))
            elseif fx.phase == "closing" then
                reach = sin(pi * Clamp01(t / 0.3)) * 0.8
            end
            if reach > 0 then
                local length = 70 * reach
                local side = tendril[1]
                -- each grips the rift's edge and reaches out past it, a little wavy
                Put(fx, texture, side * (rx + length / 2 - 6), tendril[2] + 3 * sin(GetTime() * 6 + index), length, 18, reach)
            else
                Off(texture)
            end
        end
        if tearing and Chance(25, dt) then
            local side = math.random() < 0.5 and -1 or 1
            Part(fx, "sparkle", side * rx, Random(-ry * 0.8, ry * 0.8), side * Random(20, 60), Random(-20, 20), Random(0.3, 0.5), Random(4, 7), 0.55, 0.3, 0.9)
        end
        if fx.phase == "open" and Chance(6, dt) then
            local a = Random(0, pi * 2)
            Part(fx, "sparkle", cos(a) * w * 0.45, sin(a) * h * 0.35, -cos(a) * 25, -sin(a) * 20, Random(0.8, 1.2), Random(4, 6), 0.5, 0.25, 0.8, 0.8)
        end
        if fx.phase == "closing" and t >= 0.45 and not fx.flags.shut then
            fx.flags.shut = true
            art.shutAt = GetTime()
        end
        Flash(fx, art.flash, art.shutAt, 0.17, 0, 0, 30, 80, 1)
        MoveReel(fx, fx.phase == "closing" and 60 * (1 - Clamp01(t / 0.3)) or 60, dt)
        DressCells(fx, 0, false, false, 1, 0)
    end,
}))

-- --- Demonic Gateway (Demonology warlock): a gateway opens and pulls the gates through; imp eyes peek out ---------------

local EYES = { { -62, 18 }, { 58, -14 }, { -20, -26 } }

Register("demonology", "Demonic Gateway", "WARLOCK", 266, HoleStyle("demonology", {
    openFor = 0.8, closeFor = 0.55,
    Build = function(fx, art)
        art.swirl = Tex(art, fx.window, "CaseRunes", "ADD", 0.45, 1, 0.3, "BORDER", 1)
        art.core = Tex(art, fx.window, "CaseGlow", "ADD", 0.5, 0.2, 0.9, "BORDER", 2)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 0.55, 1, 0.35, "OVERLAY", 1)
        art.runes = Tex(art, fx.top, "CaseRunes", "ADD", 0.75, 0.4, 1, "OVERLAY", 2)
        art.eyes = {}
        for index = 1, #EYES do
            art.eyes[index] = Tex(art, fx.mid, "CaseEyes", "ADD", 1, 0.72, 0.12)
        end
    end,
    Masked = function(art)
        return { art.swirl, art.core }
    end,
    Enter = function(fx, art)
        K.FaceMode(fx, "squash")
        Mood(fx, { 0.03, 0.06, 0.02 }, { 0.5, 1, 0.35 }, 0.6)
        Put(fx, art.swirl, 0, 0, 150, 150, 0.4)
        Put(fx, art.core, 0, 0, 130, 110, 0.5)
        art.blink = Random(0.4, 1.0)
        art.eye, art.eyeAge = nil, 0
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * EaseOutCubic((t - 0.15) / 0.6)
        elseif fx.phase == "open" then
            return fx.rmax + 20
        end
        return fx.rmax * (1 - EaseInCubic(t / 0.45))
    end,
    Update = function(fx, art, dt, r)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        -- the gates are pulled in toward the gateway, glowing green, and spring back as it closes
        local pull = Clamp01(r / fx.rmax)
        local fw, fh = w * (1 - 0.3 * pull), h * (1 - 0.3 * pull)
        fx.topDoor.face:SetSize(fw, fh)
        fx.bottomDoor.face:SetSize(fw, fh)
        K.FaceTint(fx, 1 - 0.35 * pull, 1, 1 - 0.4 * pull)
        local opening = fx.phase == "opening" and t < 0.15
        if r < fx.rmax or opening then
            local ring = max(r, opening and 30 * t / 0.15 or 0)
            art.runes:SetRotation(GetTime() * 4)
            Rim(fx, art.ring, ring, ring, 1 / 0.965, 1)
            Rim(fx, art.runes, ring + 6, ring + 6, 1 / 0.92, 0.9)
            if Chance(30, dt) then
                local a = Random(0, pi * 2)
                Part(fx, "sparkle", cos(a) * ring, sin(a) * ring, -sin(a) * 60, cos(a) * 60, Random(0.3, 0.5), Random(5, 7), 0.55, 1, 0.35)
            end
        else
            Off(art.ring)
            Off(art.runes)
        end
        art.swirl:SetRotation(-GetTime() * 1.2)
        -- imps peek out of the gateway and blink
        if fx.phase == "open" then
            art.blink = art.blink - dt
            if art.blink <= 0 then
                art.blink = Random(0.6, 1.4)
                art.eye = math.random(#EYES)
                art.eyeAge = 0
            end
            for index, eye in ipairs(EYES) do
                local texture = art.eyes[index]
                local alpha = 0
                if index == art.eye then
                    art.eyeAge = art.eyeAge + dt / #EYES
                    local age = art.eyeAge
                    alpha = Clamp01(age / 0.1) * (1 - Clamp01((age - 0.5) / 0.15))
                    if age > 0.25 and age < 0.3 then
                        alpha = 0.1
                    end
                end
                if alpha > 0 then
                    Put(fx, texture, eye[1], eye[2], 20, 10, alpha)
                else
                    Off(texture)
                end
            end
        else
            for _, texture in ipairs(art.eyes) do
                Off(texture)
            end
        end
        MoveReel(fx, fx.phase == "closing" and 70 * (1 - Clamp01(t / 0.35)) or 70, dt)
        DressCells(fx, 0, false, false, 1, 0)
    end,
}))

-- --- Corruption (Affliction warlock): dark rot spreads over the gates, and faint souls drift up -------------------------

Register("affliction", "Corruption", "WARLOCK", 265, HoleStyle("affliction", {
    shape = "CaseRot", fill = 0.62, openFor = 1.1, closeFor = 0.85,
    Build = function(fx, art)
        art.rim = Tex(art, fx.top, "CaseRotRim", "ADD", 0.5, 0.2, 0.65, "OVERLAY", 1)
        art.stain = Tex(art, fx.top, "CaseRotRim", "BLEND", 0.12, 0.05, 0.14, "OVERLAY", 0)
    end,
    Enter = function(fx)
        Mood(fx, { 0.03, 0.02, 0.04 }, { 0.72, 0.42, 0.85 }, 0.6)
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * EaseInOut(t / 1.05)
        elseif fx.phase == "open" then
            return fx.rmax + 30
        end
        return fx.rmax * (1 - EaseInOut(t / 0.8))
    end,
    Update = function(fx, art, dt, r)
        local h = fx.slotHeight
        -- the gates wither, grey and purple, as the rot spreads
        local rot = Clamp01(r / fx.rmax * 1.5)
        K.FaceTint(fx, 1 - 0.3 * rot, 1 - 0.45 * rot, 1 - 0.2 * rot, rot > 0.6)
        local size = 2 * r / 0.62
        if r > 0.5 and r < fx.rmax then
            art.rim:SetRotation(GetTime() * 0.3)
            art.stain:SetRotation(GetTime() * 0.3)
            Put(fx, art.rim, 0, 0, size, size, 0.9)
            Put(fx, art.stain, 0, 0, size * 1.12, size * 1.12, 0.8)
            -- souls slip free of the rot and drift up
            if Chance(10, dt) then
                local a = Random(0, pi * 2)
                local p = Part(fx, "soul", cos(a) * r * 0.9, sin(a) * r * 0.6, Random(-10, 10), Random(18, 40), Random(0.8, 1.2), Random(10, 14), 0.7, 1, 0.78, 0.7)
                if p then
                    p.grow = 0.2
                end
            end
            if Chance(6, dt) then
                local a = Random(0, pi * 2)
                Smoke(fx, cos(a) * r, sin(a) * r * 0.7, cos(a) * 10, sin(a) * 10 + 10, Random(0.6, 0.9), Random(26, 36), 0.4, 0.2, 0.08, 0.24)
            end
        else
            Off(art.rim)
            Off(art.stain)
        end
        if fx.phase == "open" and Chance(4, dt) then
            local p = Part(fx, "soul", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-6, 6), Random(16, 30), Random(1.2, 1.8), Random(10, 13), 0.7, 1, 0.78, 0.6)
            if p then
                p.grow = 0.2
            end
        end
        MoveReel(fx, 50, dt)
        DressCells(fx, 0, false, false, 1.5, 0)
    end,
}))

-- --- Inferno (Fire mage): a fireball streaks in and hits the lock; the gates char from the hole outward ---------------

local FIREBALL_ANGLE = -atan2(126 / 2 + 20, 219 / 2 + 20)

Register("fire", "Inferno", "MAGE", 63, HoleStyle("fire", {
    shape = "CaseBlob", fill = 0.68, openFor = 0.95, closeFor = 0.75,
    Build = function(fx, art)
        art.char = Tex(art, fx.top, "CaseBlobRim", "BLEND", 0.1, 0.05, 0.02, "OVERLAY", 0)
        art.rim = Tex(art, fx.top, "CaseBlobRim", "ADD", 1, 0.5, 0.1, "OVERLAY", 1)
        art.tail = Tex(art, fx.top, "CaseComet", "ADD", 1, 0.45, 0.08, "OVERLAY", 2)
        art.core = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.95, 0.6, "OVERLAY", 3)
        art.light = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.55, 0.15, "OVERLAY", 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.75, 0.35, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.06, 0.025, 0.01 }, { 1, 0.55, 0.15 }, 0.8)
        art.hitAt = nil
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * EaseOutCubic((t - 0.3) / 0.62)
        elseif fx.phase == "open" then
            return fx.rmax + 30
        end
        return fx.rmax * (1 - EaseInOut(t / 0.65))
    end,
    Update = function(fx, art, dt, r)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" and t < 0.3 then
            -- the fireball streaks in from the top left, lighting the gates as it comes
            local k = EaseInCubic(t / 0.3)
            local x, y = (-w / 2 - 20) * (1 - k), (h / 2 + 20) * (1 - k)
            local wobble = 1 + 0.1 * sin(t * 50)
            PutTurned(fx, art.tail, x - 26, y + 16, 110 * wobble, FIREBALL_ANGLE, 0.95)
            Put(fx, art.core, x, y, 28 * wobble, 28 * wobble, 1)
            Put(fx, art.light, x * 0.5, y * 0.5, 170, 120, 0.2 + 0.4 * k)
            if Chance(50, dt) then
                Part(fx, "spark", x, y, Random(-140, -50), Random(30, 110), Random(0.25, 0.4), Random(9, 12), 1, Random(0.45, 0.8), 0.15)
            end
        else
            Off(art.tail)
            Off(art.core)
            Off(art.light)
            if fx.phase == "opening" and not fx.flags.hit then
                fx.flags.hit = true
                fx.shake = 1.6
                art.hitAt = GetTime()
                Sparks(fx, 14, 0, 0, 0, pi, 100, 240, 1, 0.65, 0.2, 200)
                Burst(fx, "ember", 8, 0, 0, 50, 140, 0.6, 7, 1, 0.6, 0.15)
            end
        end
        Flash(fx, art.flash, art.hitAt, 0.22, 0, 0, 120, 100, 1)
        -- the gates scorch: hot first, then charred
        local burn = Clamp01(r / fx.rmax * 1.4)
        K.FaceTint(fx, 1 - 0.35 * burn, 1 - 0.55 * burn, 1 - 0.75 * burn)
        local size = 2 * r / 0.68
        if r > 0.5 and r < fx.rmax then
            local flicker = 0.85 + 0.15 * sin(GetTime() * 23)
            Put(fx, art.rim, 0, 0, size, size, flicker)
            Put(fx, art.char, 0, 0, size * 1.1, size * 1.1, 0.9)
            if Chance(26, dt) then
                local a = Random(0, pi * 2)
                Part(fx, "ember", cos(a) * r * 0.95, sin(a) * r * 0.7, Random(-10, 10), Random(30, 80), Random(0.5, 0.9), Random(3, 5), 1, Random(0.45, 0.85), 0.15)
            end
            if fx.phase == "closing" and Chance(10, dt) then
                local p = Part(fx, "chip", Random(-w / 2, w / 2), Random(-h / 2, h / 2), Random(-5, 5), Random(-20, -5), Random(0.5, 0.8), Random(3, 5), 0.2, 0.18, 0.16, 0.8)
                if p then
                    p.g = -80
                end
            end
        else
            Off(art.rim)
            Off(art.char)
        end
        if fx.phase == "open" and Chance(12, dt) then
            Part(fx, "ember", Random(-fx.windowWidth / 2 + 4, fx.windowWidth / 2 - 4), -h / 2 + GATE_CORNER, Random(-6, 6), Random(25, 50), Random(0.8, 1.3), Random(4, 6), 1, Random(0.45, 0.8), 0.15)
        end
        if fx.phase == "closing" and t >= 0.66 and not fx.flags.smoke then
            fx.flags.smoke = true
            Smoke(fx, 0, 0, 0, 20, 0.8, 40, 0.5, 0.35, 0.33, 0.32)
        end
        MoveReel(fx, 100, dt)
        DressCells(fx, 0, false, false, 0, fx.phase == "open" and 1.2 or 0.5)
        K.Shake(fx, dt)
    end,
}))

-- --- Halo (Holy priest): a ring of light spreads from the centre and dissolves the gates as it passes ----------------

Register("holypriest", "Halo", "PRIEST", 257, HoleStyle("holypriest", {
    openFor = 0.9, closeFor = 0.75,
    Build = function(fx, art)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.95, 0.72, "OVERLAY", 1)
        art.outer = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.85, 0.55, "OVERLAY", 2)
        art.light = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.97, 0.85, "OVERLAY", 3)
        art.warm = Tex(art, fx.window, "CaseGlow", "ADD", 1, 0.9, 0.6, "BORDER", 1)
    end,
    Masked = function(art)
        return { art.warm }
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.045, 0.03 }, { 1, 0.95, 0.7 })
        Put(fx, art.warm, 0, 0, fx.windowWidth * 1.1, fx.slotHeight * 1.2, 0.25)
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * 1.15 * EaseOutCubic((t - 0.12) / 0.75)
        elseif fx.phase == "open" then
            return fx.rmax + 30
        end
        return fx.rmax * 1.15 * (1 - EaseInOut(t / 0.65))
    end,
    Update = function(fx, art, dt, r)
        local t = fx.t
        local h = fx.slotHeight
        -- the gates warm in the light
        local lit = Clamp01(r / fx.rmax * 2)
        K.FaceTint(fx, 1, 1 - 0.05 * lit, 1 - 0.18 * lit)
        if fx.phase == "opening" and t < 0.3 then
            local k = Clamp01(t / 0.12)
            Put(fx, art.light, 0, 0, 30 + 50 * k, 30 + 50 * k, k * (1 - Clamp01((t - 0.12) / 0.18)))
        elseif fx.phase == "closing" and t > 0.6 then
            local k = Clamp01((t - 0.6) / 0.15)
            Put(fx, art.light, 0, 0, 80 - 50 * k, 80 - 50 * k, 1 - k)
        else
            Off(art.light)
        end
        if r > 0.5 and r < fx.rmax * 1.1 then
            Rim(fx, art.ring, r, r, 1 / 0.965, 1)
            Rim(fx, art.outer, r + 10, r + 10, 1 / 0.965, 0.35)
            if Chance(30, dt) then
                local a = Random(0, pi * 2)
                Part(fx, "sparkle", cos(a) * r, sin(a) * r, cos(a) * 30, sin(a) * 30, Random(0.3, 0.5), Random(5, 7), 1, 0.95, 0.75)
            end
        else
            Off(art.ring)
            Off(art.outer)
        end
        art.warm:SetAlpha(0.2 + 0.08 * sin(GetTime() * 2))
        if fx.phase == "open" and Chance(6, dt) then
            Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-4, 4), Random(14, 26), Random(0.8, 1.3), Random(4, 6), 1, 0.95, 0.7, 0.8)
        end
        MoveReel(fx, 70, dt)
        DressCells(fx, 0, false, false, 1, 0)
    end,
}))

-- --- Eclipse (Balance druid): the moon slides over the sun, the gates dim; at totality the corona flares and they open --

Register("balance", "Eclipse", "DRUID", 102, HoleStyle("balance", {
    openFor = 1.15, closeFor = 0.6,
    Build = function(fx, art)
        art.rays = Tex(art, fx.top, "CaseRays", "ADD", 0.75, 0.8, 1, "OVERLAY", 0)
        art.sun = Tex(art, fx.top, "CaseSun", "BLEND", nil, nil, nil, "OVERLAY", 1)
        art.corona = Tex(art, fx.top, "CaseRing", "ADD", 0.78, 0.82, 1, "OVERLAY", 2)
        art.moon = Tex(art, fx.top, "CaseMoon", "BLEND", 0.55, 0.58, 0.75, "OVERLAY", 3)
        art.diamond = Tex(art, fx.top, "CaseSparkle", "ADD", 1, 1, 1, "OVERLAY", 4)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 0.72, 0.62, 1, "OVERLAY", 5)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.03, 0.03, 0.07 }, { 0.75, 0.65, 1 }, 0.7)
        art.flashAmount = 0
    end,
    Radius = function(fx)
        local t = fx.t
        if fx.phase == "opening" then
            return fx.rmax * EaseOutBack((t - 0.72) / 0.42, 1.2)
        elseif fx.phase == "open" then
            return fx.rmax + 20
        end
        return fx.rmax * (1 - EaseInCubic(t / 0.5))
    end,
    Update = function(fx, art, dt, r)
        local t = fx.t
        if fx.phase == "opening" then
            local fade = 1 - Clamp01((t - 0.72) / 0.15)
            local mx = -90 * (1 - EaseOutCubic((t - 0.08) / 0.6))
            local total = Clamp01(1 - abs(mx) / 30)
            -- the gates dim as the moon covers the sun
            K.FaceTint(fx, 1 - 0.55 * total, 1 - 0.55 * total, 1 - 0.4 * total)
            Put(fx, art.sun, 0, 0, 58, 58, fade)
            Put(fx, art.moon, mx, 0, 46, 46, fade)
            art.rays:SetRotation(t * 0.6)
            Put(fx, art.rays, 0, 0, 150 + 30 * total, 150 + 30 * total, total * fade * 0.8)
            Put(fx, art.corona, 0, 0, 58 + 8 * total, 58 + 8 * total, total * fade)
            -- the diamond ring: one bright point on the edge just before totality
            local diamond = Clamp01(1 - abs(mx + 6) / 6) * fade
            if diamond > 0 then
                art.diamond:SetRotation(t * 3)
                Put(fx, art.diamond, mx + 22, 4, 26 * diamond + 6, 26 * diamond + 6, diamond)
            else
                Off(art.diamond)
            end
            if t >= 0.72 and not fx.flags.totality then
                fx.flags.totality = true
                art.flashAmount = 1
                Burst(fx, "sparkle", 10, 0, 0, 50, 120, 0.6, 7, 0.85, 0.8, 1)
            end
        else
            Off(art.sun)
            Off(art.moon)
            Off(art.rays)
            Off(art.corona)
            Off(art.diamond)
        end
        if r > 0.5 and r < fx.rmax then
            Rim(fx, art.ring, r, r, 1 / 0.965, 0.9)
        elseif art.flashAmount <= 0 then
            Off(art.ring)
        end
        art.flashAmount = max(0, art.flashAmount - dt * 3)
        if art.flashAmount > 0 and r >= fx.rmax then
            Rim(fx, art.ring, fx.rmax, fx.rmax, 1 / 0.965, art.flashAmount)
        end
        -- stars twinkle, purple and gold
        if fx.phase == "open" and Chance(9, dt) then
            local gold = math.random() < 0.5
            local p = Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), Random(-fx.slotHeight / 2 + 20, fx.slotHeight / 2 - 20), 0, 0, Random(0.5, 0.9), Random(5, 8),
                gold and 1 or 0.75, gold and 0.85 or 0.55, gold and 0.4 or 1, 0.9)
            if p then
                p.grow = -0.5
            end
        end
        MoveReel(fx, fx.phase == "opening" and (t < 0.72 and 0 or 60) or 60, dt)
        DressCells(fx, 0, false, false, 0, 0)
    end,
}))

-- =============================================================================================================
-- Gates that slide apart
-- =============================================================================================================

-- How far the gates have gone: opening from `from` over `over` (with `ease`), and shutting over
-- `close` once closing.
local function Swing(fx, from, over, close, ease)
    if fx.phase == "opening" then
        return (ease or EaseInOut)((fx.t - from) / over)
    elseif fx.phase == "open" then
        return 1
    end
    return 1 - EaseInCubic(fx.t / close)
end

-- --- Divine Light (Holy paladin): golden light through the seam; the gates part as wings unfold from it ----------------

Register("holypaladin", "Divine Light", "PALADIN", 65, SlideStyle("holypaladin", {
    openFor = 1.05, closeFor = 0.6, seams = true,
    Build = function(fx, art)
        art.rays = Tex(art, fx.mid, "CaseRays", "ADD", 1, 0.85, 0.45)
        art.light = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.9, 0.6, "OVERLAY", 0)
        art.seam = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.88, 0.5, "OVERLAY", 1)
        art.right = Tex(art, fx.top, "CaseWing", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.left = Tex(art, fx.top, "CaseWing", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.left:SetTexCoord(1, 0, 0, 1)
    end,
    Enter = function(fx)
        Mood(fx, { 0.08, 0.06, 0.025 }, { 1, 0.85, 0.45 })
        K.ColorTexture(fx.topSeam.line, 1, 0.85, 0.45, 1)
        K.ColorTexture(fx.bottomSeam.line, 1, 0.85, 0.45, 1)
    end,
    Reveal = function(fx)
        return Swing(fx, 0.3, 0.7, 0.5)
    end,
    Update = function(fx, art, dt, top)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local unfold = 0
        if fx.phase == "opening" then
            local glow = Clamp01(t / 0.3)
            Put(fx, art.seam, 0, h / 2 - top, w * (0.2 + 1.1 * glow), 10 + 30 * glow, glow * (1 - Clamp01((t - 0.5) / 0.4)))
            Put(fx, art.light, 0, 0, w * 1.3, h * 1.4, glow * 0.35 * (1 - Clamp01((t - 0.5) / 0.4)))
            K.FaceTint(fx, 1, 1 - 0.06 * glow, 1 - 0.22 * glow)
            if Chance(20 * glow, dt) then
                Part(fx, "sparkle", Random(-w / 2 + 10, w / 2 - 10), h / 2 - top, Random(-8, 8), Random(-30, 30), Random(0.4, 0.7), Random(4, 6), 1, 0.9, 0.55)
            end
            unfold = EaseOutBack((t - 0.3) / 0.45, 1.2) * (1 - Clamp01((t - 0.75) / 0.25))
        else
            Off(art.seam)
            Off(art.light)
            if fx.phase == "closing" then
                unfold = 1 - Clamp01(t / 0.3)
            end
        end
        -- the wings: folded down at the seam, they open up and out as the gates part
        if unfold > 0.02 then
            local angle = -1.5 + 1.6 * unfold
            local size = 60 + 56 * Clamp01(unfold)
            local alpha = Clamp01(unfold * 2)
            PutTurned(fx, art.right, 6, 0, size, angle, alpha)
            PutTurned(fx, art.left, -6, 0, size, -angle, alpha)
            if fx.phase == "opening" and Chance(14, dt) then
                local side = math.random() < 0.5 and -1 or 1
                local p = Part(fx, "petal", side * Random(20, 60), Random(0, 40), side * Random(5, 20), Random(-20, -5), Random(0.8, 1.2), Random(5, 7), 1, 0.92, 0.7, 0.9)
                if p then
                    p.g, p.grow = -40, 0
                end
            end
        else
            Off(art.right)
            Off(art.left)
        end
        local rays = fx.phase == "opening" and Clamp01((t - 0.2) / 0.5) or fx.phase == "open" and 1 or 1 - Clamp01(t / 0.4)
        art.rays:SetRotation(GetTime() * 0.25)
        Put(fx, art.rays, 0, 0, 240, 240, 0.35 * rays)
        if fx.phase == "open" and Chance(6, dt) then
            Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), -h / 2 + GATE_CORNER, Random(-4, 4), Random(15, 30), Random(0.8, 1.2), Random(4, 6), 1, 0.85, 0.45, 0.8)
        end
        if fx.phase == "closing" and t >= 0.5 and not fx.flags.shut then
            fx.flags.shut = true
            SparksAlong(fx, 6, 0, 0, 0, w * 0.8, 1, 0.9, 0.55, 0)
        end
        MoveReel(fx, fx.phase == "opening" and 80 * Clamp01((t - 0.3) / 0.4) or 80, dt)
        DressCells(fx, 0, false, false, 0, 0)
    end,
}))

-- --- Bullseye (Marksmanship hunter): the world narrows to the lock, an arrow thuds into it, the gates spring apart -----

Register("marksmanship", "Bullseye", "HUNTER", 254, SlideStyle("marksmanship", {
    openFor = 1.05, closeFor = 0.5, seams = true,
    Build = function(fx, art)
        art.dark = Tex(art, fx.top, "CaseVignette", "BLEND", 0, 0, 0, "OVERLAY", 0)
        art.ring = Tex(art, fx.top, "CaseScopeRing", "ADD", 1, 0.4, 0.25, "OVERLAY", 1)
        art.sight = Tex(art, fx.top, "CaseCrosshair", "ADD", 1, 0.45, 0.3, "OVERLAY", 2)
        art.dot = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.2, 0.15, "OVERLAY", 3)
        art.trail = Tex(art, fx.top, "CaseSlashCore", "ADD", 1, 1, 1, "OVERLAY", 3)
        art.ghost = Tex(art, fx.top, "CaseArrowShot", "BLEND", nil, nil, nil, "OVERLAY", 4)
        art.arrow = Tex(art, fx.top, "CaseArrowShot", "BLEND", nil, nil, nil, "OVERLAY", 5)
        art.hit = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.9, 0.75, "OVERLAY", 5)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.9, 0.75, "OVERLAY", 5)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.03, 0.04, 0.03 }, { 1, 0.4, 0.25 })
        K.EnsureMarkerGlow(fx)
        art.arrowY, art.arrowVY, art.arrowSpin, art.hitAt = 0, 0, 0, nil
    end,
    Reveal = function(fx)
        if fx.phase == "opening" then
            return EaseOutBack((fx.t - 0.64) / 0.38, 1.8)
        end
        return Swing(fx, 0, 1, 0.4)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local speed = 80
        if fx.phase == "opening" then
            -- the edges darken and the sight closes in on the lock, steadying
            local aim = EaseOutCubic(t / 0.48)
            local jitter = 5 * (1 - aim)
            local fade = 1 - Clamp01((t - 0.56) / 0.15)
            Put(fx, art.dark, 0, 0, w * 1.05, h * 1.1, 0.65 * Clamp01(t / 0.2) * (1 - Clamp01((t - 0.58) / 0.2)))
            local jx, jy = Random(-jitter, jitter), Random(-jitter, jitter)
            art.ring:SetRotation(t * 1.2)
            Put(fx, art.ring, jx, jy, 220 - 140 * aim, 220 - 140 * aim, (0.4 + 0.6 * aim) * fade)
            art.sight:SetRotation(-0.6 * (1 - aim))
            Put(fx, art.sight, jx, jy, 200 - 140 * aim, 200 - 140 * aim, (0.5 + 0.5 * aim) * fade)
            local dot = 7 + 3 * sin(t * 30)
            Put(fx, art.dot, jx, jy, dot, dot, aim * fade)
            if t >= 0.48 and t < 0.56 then
                -- the arrow: in from the right, its streak behind it
                local k = (t - 0.48) / 0.08
                local x = (w / 2 + 40) * (1 - k) + 32 * k
                PutTurned(fx, art.arrow, x, 0, 64, 0, 1)
                PutTurned(fx, art.ghost, x + 26, 0, 64, 0, 0.3)
                PutTurned(fx, art.trail, x + 70, 0, 130, 0, 0.6)
            elseif t >= 0.56 then
                if not art.hitAt then
                    art.hitAt = GetTime()
                    fx.shake = 1.4
                    Sparks(fx, 8, 0, 0, 0, 1.2, 60, 160, 1, 0.8, 0.5, 300)
                    Chips(fx, 4, 0, 0, 30, 90, 4, 0.55, 0.38, 0.2)
                    art.arrowY, art.arrowVY, art.arrowSpin = 0, 30, 0
                end
                Off(art.ghost)
                Off(art.trail)
                local stuck = t - 0.56
                if t < 0.66 then
                    -- it quivers in the lock
                    PutTurned(fx, art.arrow, 32, 0, 64, 0.1 * sin(stuck * 70) * (1 - stuck / 0.1), 1)
                else
                    -- the gates spring apart and it drops, turning
                    art.arrowVY = art.arrowVY - 500 * dt
                    art.arrowY = art.arrowY + art.arrowVY * dt
                    art.arrowSpin = art.arrowSpin - dt * 3
                    PutTurned(fx, art.arrow, 32, art.arrowY, 64, art.arrowSpin, 1 - Clamp01((t - 0.75) / 0.2))
                end
            else
                Off(art.arrow)
            end
            speed = t < 0.64 and 0 or 80 + 200 * (1 - Clamp01((t - 0.64) / 0.4))
        else
            Off(art.dark)
            Off(art.ring)
            Off(art.sight)
            Off(art.dot)
            Off(art.arrow)
            Off(art.ghost)
            Off(art.trail)
            if fx.phase == "closing" and t >= 0.4 and not fx.flags.shut then
                fx.flags.shut = true
                fx.shake = 0.8
                Smoke(fx, 0, 0, 0, 15, 0.5, 30, 0.35, 0.7, 0.65, 0.55)
            end
        end
        Ring(fx, art.hit, art.hitAt, 0.3, 0, 0, 16, 90, 1, 0.9)
        Flash(fx, art.flash, art.hitAt, 0.18, 0, 0, 70, 60, 0.8)
        if fx.markerGlow then
            fx.markerGlow:SetAlpha(fx.phase == "open" and fx.pulse * 0.8 or 0)
        end
        MoveReel(fx, speed, dt)
        DressCells(fx, 0.18, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Beast Bite (Beast Mastery hunter): jaws snap shut on the lock, shake it, and tear the gates away ------------------

local JAW_H = 62

Register("beastmastery", "Beast Bite", "HUNTER", 253, SlideStyle("beastmastery", {
    openFor = 1.0, closeFor = 0.5,
    Build = function(fx, art)
        art.dark = Tex(art, fx.top, "CaseVignette", "BLEND", 0, 0, 0, "OVERLAY", 0)
        art.upper = Tex(art, fx.top, "CaseJawUpper", "BLEND", nil, nil, nil, "OVERLAY", 1)
        art.lower = Tex(art, fx.top, "CaseJawLower", "BLEND", nil, nil, nil, "OVERLAY", 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.2, 0.15, "OVERLAY", 2)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.03, 0.02 }, { 0.95, 0.55, 0.25 })
        art.bitAt = nil
    end,
    Reveal = function(fx)
        return Swing(fx, 0.34, 0.5, 0.4)
    end,
    Update = function(fx, art, dt, top, bottom)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            Put(fx, art.dark, 0, 0, w * 1.05, h * 1.1, 0.55 * Clamp01(t / 0.12) * (1 - Clamp01((t - 0.3) / 0.15)))
            -- the jaws gape at the edges, then snap shut on the lock
            local gap, thrash = 0, 0
            if t < 0.22 then
                gap = 46 * (1 - EaseInCubic(t / 0.22))
                if Chance(12, dt) then
                    Smoke(fx, Random(-30, 30), Random(-10, 10), Random(-20, 20), Random(-8, 8), Random(0.5, 0.8), Random(26, 36), 0.18, 0.85, 0.85, 0.85)
                end
            elseif t < 0.34 then
                if not art.bitAt then
                    art.bitAt = GetTime()
                    fx.shake = 2.4
                    Burst(fx, "drop", 6, 0, 0, 40, 110, 0.5, 8, 0.7, 0.05, 0.05)
                    Chips(fx, 4, 0, 0, 40, 110, 40)
                end
                -- it shakes the lock like prey
                thrash = 3.5 * sin(t * 70)
                fx.shake = max(fx.shake or 0, 0.8)
            end
            local upperY, lowerY
            if t < 0.34 then
                upperY, lowerY = gap + 12, -gap - 12
            else
                -- the jaws pull back out with the gates in their teeth
                upperY, lowerY = (h / 2 - top) + 12, -(h / 2 - bottom) - 12
                if Chance(18, dt) then
                    Chips(fx, 1, Random(-w / 2 + 20, w / 2 - 20), 0, 20, 70, 0)
                end
            end
            local alpha = 1 - Clamp01((t - 0.75) / 0.2)
            Put(fx, art.upper, thrash, upperY, w + 30, JAW_H, alpha)
            Put(fx, art.lower, -thrash, lowerY, w + 30, JAW_H, alpha)
        else
            Off(art.dark)
            Off(art.upper)
            Off(art.lower)
            if fx.phase == "closing" and t >= 0.4 and not fx.flags.shut then
                fx.flags.shut = true
                fx.shake = 1.2
                for side = -1, 1, 2 do
                    Smoke(fx, side * Random(30, 80), 0, side * Random(20, 50), Random(-10, 10), 0.6, 32, 0.45, 0.7, 0.62, 0.5)
                end
            end
        end
        Flash(fx, art.flash, art.bitAt, 0.25, 0, 0, w * 0.8, 70, 0.7)
        MoveReel(fx, fx.phase == "opening" and (t < 0.34 and 0 or 110) or 110, dt)
        DressCells(fx, 0.06, false, true, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Steel Trap (Survival hunter): trap jaws slam shut from the sides in a burst of sparks and spring back, dragging the gates

local TRAP_W = 32

Register("survival", "Steel Trap", "HUNTER", 255, SlideStyle("survival", {
    columns = true, openFor = 0.9, closeFor = 0.5,
    Build = function(fx, art)
        art.ghostL = Tex(art, fx.top, "CaseTrapJaw", "BLEND", nil, nil, nil, "OVERLAY", 1)
        art.ghostR = Tex(art, fx.top, "CaseTrapJaw", "BLEND", nil, nil, nil, "OVERLAY", 1)
        art.left = Tex(art, fx.top, "CaseTrapJaw", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.right = Tex(art, fx.top, "CaseTrapJaw", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.right:SetTexCoord(1, 0, 0, 1)
        art.ghostR:SetTexCoord(1, 0, 0, 1)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 1, 1, "OVERLAY", 3)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.95, 0.85, "OVERLAY", 3)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.035, 0.035, 0.03 }, { 0.85, 0.9, 0.95 })
        K.EnsureGhosts(fx)
        art.snapAt = nil
    end,
    Reveal = function(fx)
        return Swing(fx, 0.28, 0.48, 0.4, EaseOutCubic)
    end,
    Update = function(fx, art, dt, left, right)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local tips = TRAP_W * 0.46 -- the teeth's tips from the jaw's middle
        if fx.phase == "opening" then
            local reachL, reachR, alpha = 0, 0, 1 - Clamp01((t - 0.7) / 0.2)
            if t < 0.18 then
                local reach = (w / 2 + 20) * (1 - EaseInCubic(t / 0.18))
                reachL, reachR = reach, reach
                Put(fx, art.ghostL, -reach - tips - 18, 0, TRAP_W, h + 12, 0.35)
                Put(fx, art.ghostR, reach + tips + 18, 0, TRAP_W, h + 12, 0.35)
            else
                Off(art.ghostL)
                Off(art.ghostR)
                if not art.snapAt then
                    art.snapAt = GetTime()
                    fx.shake = 2.6
                    for _ = 1, 16 do
                        local up = math.random() < 0.5 and 0 or pi
                        Sparks(fx, 1, Random(-3, 3), Random(-h / 2 + 20, h / 2 - 20), up, 0.7, 100, 250, 1, 0.75, 0.35, 300, 0.4)
                    end
                    Chips(fx, 4, 0, 0, 40, 110, 4, 0.75, 0.76, 0.8)
                end
                if t < 0.28 then
                    local rattle = Random(-1.5, 1.5)
                    reachL, reachR = rattle, -rattle
                else
                    reachL, reachR = w / 2 - left, w / 2 - right
                    -- the teeth scrape the gates' edges as they drag them
                    if Chance(30, dt) then
                        local side = math.random() < 0.5 and -1 or 1
                        local x = side * ((side < 0 and reachL or reachR))
                        Sparks(fx, 1, x, Random(-h / 2 + 10, h / 2 - 10), side < 0 and pi / 2 or -pi / 2, 0.6, 60, 140, 1, 0.75, 0.35, 200, 0.3)
                    end
                end
            end
            Put(fx, art.left, -reachL - tips, 0, TRAP_W, h + 12, alpha)
            Put(fx, art.right, reachR + tips, 0, TRAP_W, h + 12, alpha)
        else
            Off(art.left)
            Off(art.right)
            Off(art.ghostL)
            Off(art.ghostR)
            if fx.phase == "closing" and t >= 0.4 and not fx.flags.clank then
                fx.flags.clank = true
                fx.shake = 1.4
                art.snapAt = GetTime()
                for _ = 1, 6 do
                    Sparks(fx, 1, 0, Random(-h / 2 + 20, h / 2 - 20), math.random() < 0.5 and 0 or pi, 0.8, 60, 160, 1, 0.75, 0.35, 200, 0.35)
                end
            end
        end
        Flash(fx, art.flash, art.snapAt, 0.2, 0, 0, 50, h, 0.8)
        Ring(fx, art.ring, art.snapAt, 0.25, 0, 0, 20, 110, 1.4, 0.7)
        MoveReel(fx, fx.phase == "opening" and (t < 0.28 and 0 or 90) or 90, dt)
        DressCells(fx, 0, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Avenger's Shield (Protection paladin): a spinning shield flies in, knocks each gate off in turn, and flies on ---------

local function ShieldPath(t, w)
    -- in from the left to the top gate, down to the bottom gate, out to the right
    if t < 0.22 then
        local k = t / 0.22
        return -w / 2 - 30 + (w / 2 + 6) * k, 10 + 14 * k
    elseif t < 0.38 then
        local k = (t - 0.22) / 0.16
        return -24 + 44 * k, 24 - 48 * k
    end
    local k = (t - 0.38) / 0.22
    return 20 + (w / 2 + 20) * k, -24 + 50 * k
end

local SHIELD_HITS = { { 0.22, pi / 2 }, { 0.38, -pi / 2 } }

Register("protpaladin", "Avenger's Shield", "PALADIN", 66, SlideStyle("protpaladin", {
    openFor = 0.9, closeFor = 0.5, seams = true,
    Build = function(fx, art)
        art.glow = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.85, 0.45, "OVERLAY", 1)
        art.ghosts = {}
        for index = 1, 3 do
            art.ghosts[index] = Tex(art, fx.top, "CaseShieldRound", "BLEND", 1, 0.95, 0.8, "OVERLAY", 2)
        end
        art.shield = Tex(art, fx.top, "CaseShieldRound", "BLEND", nil, nil, nil, "OVERLAY", 3)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.92, 0.65, "OVERLAY", 4)
        art.seam = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.88, 0.5, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.04, 0.04, 0.06 }, { 1, 0.85, 0.45 })
        art.hitAt, art.hitX, art.hitY, art.shutAt = nil, 0, 0, nil
    end,
    Reveal = function(fx)
        if fx.phase == "opening" then
            return EaseOutBack((fx.t - 0.22) / 0.4, 1.3), EaseOutBack((fx.t - 0.38) / 0.4, 1.3)
        end
        return Swing(fx, 0, 1, 0.4)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" and t < 0.62 then
            local x, y = ShieldPath(t, w)
            local spin = -t * 22
            Put(fx, art.glow, x, y, 80, 80, 0.6)
            -- a trail of fading copies behind it
            for index, ghost in ipairs(art.ghosts) do
                local gx, gy = ShieldPath(max(0, t - 0.025 * index), w)
                PutTurned(fx, ghost, gx, gy, 40, spin + 0.55 * index, 0.45 / index)
            end
            PutTurned(fx, art.shield, x, y, 40, spin, 1)
            for index, hit in ipairs(SHIELD_HITS) do
                if t >= hit[1] and not fx.flags[index] then
                    fx.flags[index] = true
                    fx.shake = 1.3
                    art.hitAt, art.hitX, art.hitY = GetTime(), x, y
                    Sparks(fx, 10, x, y, hit[2], 0.9, 100, 240, 1, 0.9, 0.55, 150)
                    Chips(fx, 4, x, y, 40, 110, 6)
                end
            end
        else
            Off(art.glow)
            Off(art.shield)
            for _, ghost in ipairs(art.ghosts) do
                Off(ghost)
            end
        end
        Flash(fx, art.flash, art.hitAt, 0.2, art.hitX, art.hitY, 70, 70, 1)
        if fx.phase == "open" and Chance(5, dt) then
            Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), Random(-30, 30), 0, 0, Random(0.4, 0.7), Random(5, 7), 1, 0.9, 0.6, 0.7)
        end
        if fx.phase == "closing" and t >= 0.4 and not fx.flags.shut then
            fx.flags.shut = true
            art.shutAt = GetTime()
            SparksAlong(fx, 6, 0, 0, 0, w * 0.7, 1, 0.9, 0.55, 0)
        end
        Flash(fx, art.seam, art.shutAt, 0.2, 0, 0, w, 24, 0.9)
        MoveReel(fx, fx.phase == "opening" and (t < 0.22 and 0 or 80) or 80, dt)
        DressCells(fx, 0.06, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Palm Strike (Windwalker monk): chi gathers, a glowing palm strikes the centre, rings knock the gates out -----------

local PALM_RINGS = { { 0, 0.45, 1, 0.7 }, { 0.06, 1, 0.85, 0.45 }, { 0.12, 1, 1, 1 } } -- delay, color

Register("windwalker", "Palm Strike", "MONK", 269, SlideStyle("windwalker", {
    openFor = 0.75, closeFor = 0.5,
    Build = function(fx, art)
        art.chi = Tex(art, fx.top, "CaseGlow", "ADD", 0.45, 1, 0.7, "OVERLAY", 1)
        art.palm = Tex(art, fx.top, "CasePalm", "BLEND", nil, nil, nil, "OVERLAY", 2)
        art.print = Tex(art, fx.top, "CasePalm", "ADD", 0.45, 1, 0.7, "OVERLAY", 3)
        art.rings = {}
        for index, ring in ipairs(PALM_RINGS) do
            art.rings[index] = Tex(art, fx.top, "CaseRing", "ADD", ring[2], ring[3], ring[4], "OVERLAY", 4)
        end
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 0.85, 1, 0.9, "OVERLAY", 5)
        art.lines = Tex(art, fx.mid, "CaseSpeed", "ADD", 0.6, 1, 0.8)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.02, 0.05, 0.04 }, { 0.45, 1, 0.7 })
        K.EnsureGhosts(fx)
        art.strikeAt = nil
    end,
    Reveal = function(fx)
        return Swing(fx, 0.22, 0.3, 0.4, EaseOutCubic)
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local speed = 100
        if fx.phase == "opening" then
            if t < 0.22 then
                -- chi gathers into the centre; the palm comes at it
                local k = t / 0.22
                Put(fx, art.chi, 0, 0, 20 + 50 * k, 20 + 50 * k, k)
                K.FaceTint(fx, 1 - 0.25 * k, 1, 1 - 0.15 * k)
                if Chance(60, dt) then
                    local a = Random(0, pi * 2)
                    local gold = math.random() < 0.3
                    local p = Part(fx, "sparkle", cos(a) * 70, sin(a) * 45, -cos(a) * 300, -sin(a) * 200, 0.22, Random(5, 7), gold and 1 or 0.45, gold and 0.85 or 1, gold and 0.4 or 0.7)
                    if p then
                        p.drag = 1
                    end
                end
                local reach = Clamp01((t - 0.1) / 0.12)
                if reach > 0 then
                    local size = 200 - 116 * EaseInCubic(reach)
                    Put(fx, art.palm, 0, 0, size, size, reach)
                else
                    Off(art.palm)
                end
                speed = 0
            else
                if not art.strikeAt then
                    art.strikeAt = GetTime()
                    fx.shake = 1.8
                    K.FaceTint(fx, 1, 1, 1)
                    Sparks(fx, 18, 0, 0, 0, pi, 200, 380, 0.75, 1, 0.85, 0, 0.3)
                end
                Off(art.chi)
                -- the palm's print lingers, glowing, and fades
                local k = Clamp01((t - 0.22) / 0.3)
                Put(fx, art.palm, 0, 0, 84 * (1 + 0.1 * k), 84 * (1 + 0.1 * k), 1 - k)
                Put(fx, art.print, 0, 0, 92 * (1 + 0.2 * k), 92 * (1 + 0.2 * k), (1 - k) * 0.8)
                speed = 100 + 600 * (1 - Clamp01((t - 0.22) / 0.4))
            end
        else
            Off(art.chi)
            Off(art.palm)
            Off(art.print)
            if fx.phase == "closing" then
                local k = Clamp01(t / 0.45)
                local size = 220 * (1 - k) + 10
                Put(fx, art.rings[1], 0, 0, size, size * 0.75, sin(pi * k) * 0.6)
                speed = 100 * (1 - k)
            else
                Off(art.rings[1])
                if Chance(3, dt) then
                    local side = math.random() < 0.5 and -1 or 1
                    Smoke(fx, side * (fx.windowWidth / 2 - 10), Random(-25, 25), -side * Random(15, 30), Random(-4, 4), Random(1, 1.5), Random(30, 40), 0.2, 0.55, 1, 0.75)
                end
            end
        end
        if fx.phase ~= "closing" then
            for index, ring in ipairs(PALM_RINGS) do
                Ring(fx, art.rings[index], art.strikeAt and art.strikeAt + ring[1], 0.35, 0, 0, 20, 320, 0.75, 1)
            end
        else
            Off(art.rings[2])
            Off(art.rings[3])
        end
        Flash(fx, art.flash, art.strikeAt, 0.15, 0, 0, w, h, 0.8)
        art.lines:SetTexCoord((GetTime() * 0.8) % 1, (GetTime() * 0.8) % 1 + fx.windowWidth / 256, 0, 1)
        Put(fx, art.lines, 0, 0, fx.windowWidth, fx.slotHeight - 2 * GATE_CORNER, Clamp01((speed - 250) / 400) * 0.6)
        MoveReel(fx, speed, dt)
        DressCells(fx, 0, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Stormstrike (Enhancement shaman): two charged blows, crackling, knock the gates left and right; thunder closes them --

local STORM_HITS = { { 0.1, -1 }, { 0.28, 1 } }

Register("enhancement", "Stormstrike", "SHAMAN", 263, SlideStyle("enhancement", {
    columns = true, openFor = 0.75, closeFor = 0.55,
    Build = function(fx, art)
        art.glows, art.cores, art.bolts = {}, {}, {}
        for index = 1, 2 do
            art.glows[index] = Tex(art, fx.top, "CaseSlashArc", "ADD", 0.45, 0.7, 1, "OVERLAY", 1)
            art.cores[index] = Tex(art, fx.top, "CaseSlashCore", "ADD", 0.85, 0.95, 1, "OVERLAY", 2)
            art.bolts[index] = Tex(art, fx.top, "CaseBolt", "ADD", 0.7, 0.85, 1, "OVERLAY", 3)
        end
        art.clap = Tex(art, fx.top, "CaseGlow", "ADD", 0.55, 0.75, 1, "OVERLAY", 4)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 0.6, 0.8, 1, "OVERLAY", 4)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.02, 0.03, 0.06 }, { 0.5, 0.75, 1 })
        K.EnsureGhosts(fx)
        art.hitAt, art.clapAt = nil, nil
    end,
    Reveal = function(fx)
        if fx.phase == "opening" then
            return EaseOutCubic((fx.t - 0.1) / 0.3), EaseOutCubic((fx.t - 0.28) / 0.3)
        end
        return Swing(fx, 0, 1, 0.4)
    end,
    Update = function(fx, art, dt, left, right)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            for index, hit in ipairs(STORM_HITS) do
                local age = t - hit[1]
                local side = hit[2]
                local x = side * w / 4
                local sweep = side * 0.3 * (1 - EaseOutCubic(Clamp01(age / 0.06)))
                Slash(fx, art.glows[index], art.cores[index], x, 0, 160, -side * 0.9 + sweep, SlashAlpha(age))
                local alpha = SlashAlpha(age)
                if alpha > 0 then
                    local flicker = (age < 0.06 or (age > 0.1 and age < 0.14)) and 1 or 0.3
                    Put(fx, art.bolts[index], x + side * 8, 12, 20, 80, flicker * alpha)
                else
                    Off(art.bolts[index])
                end
                if age >= 0 and not fx.flags[index] then
                    fx.flags[index] = true
                    fx.shake = 1.5
                    art.hitAt = GetTime()
                    Sparks(fx, 10, x, 0, side < 0 and pi or 0, 0.8, 120, 260, 0.7, 0.88, 1, 100)
                end
            end
            -- the gates flash blue at each blow, and lightning crawls on them as they go
            local flash = Since(art.hitAt, 0.14)
            K.FaceTint(fx, 1 - 0.3 * flash, 1 - 0.15 * flash, 1)
            if t > 0.1 and Chance(30, dt) then
                local side = math.random() < 0.5 and -1 or 1
                local edge = side < 0 and (-w / 2 + left) or (w / 2 - right)
                local p = Part(fx, "spark", edge, Random(-h / 2 + 6, h / 2 - 6), Random(-40, 40), Random(-60, 60), Random(0.12, 0.2), Random(8, 11), 0.7, 0.88, 1)
                if p then
                    p.drag = 0.9
                end
            end
        else
            for index = 1, 2 do
                Off(art.glows[index])
                Off(art.cores[index])
                Off(art.bolts[index])
            end
            if fx.phase == "closing" and t >= 0.4 and not art.clapAt then
                art.clapAt = GetTime()
                fx.shake = 1.4
                Sparks(fx, 10, 0, 0, pi / 2, pi, 80, 200, 0.7, 0.88, 1, 0)
            end
            if fx.phase == "open" and Chance(4, dt) then
                Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), Random(-30, 30), Random(-20, 20), Random(-20, 20), Random(0.2, 0.35), Random(4, 6), 0.65, 0.85, 1)
            end
        end
        Flash(fx, art.clap, art.clapAt, 0.25, 0, 0, 80, h, 1)
        Ring(fx, art.ring, art.clapAt, 0.35, 0, 0, 20, 260, 0.6, 0.8)
        MoveReel(fx, fx.phase == "opening" and (t < 0.1 and 0 or 110) or 110, dt)
        DressCells(fx, 0, true, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Bloom (Restoration druid): vines grow over the gates from both sides, buds open into flowers, the gates part ------

-- Vines: from which side, how high, when they start; flowers: where, when the bud appears, pink or white.
local VINES = { { -1, 26, 0 }, { 1, 6, 0.06 }, { -1, -18, 0.12 }, { 1, -36, 0.18 } }
local BLOOMS = { { -70, 26, 0.3, true }, { -22, 26, 0.36 }, { 54, 6, 0.33, true }, { 12, 6, 0.42 }, { -58, -18, 0.4 }, { -8, -18, 0.47, true }, { 40, -36, 0.45 } }

Register("restodruid", "Bloom", "DRUID", 105, SlideStyle("restodruid", {
    columns = true, openFor = 1.15, closeFor = 0.6,
    Build = function(fx, art)
        art.vines, art.buds, art.flowers = {}, {}, {}
        for index in ipairs(VINES) do
            local vine = Tex(art, fx.top, nil, "BLEND", nil, nil, nil, "OVERLAY", 1)
            vine:SetTexture(MEDIA .. "CaseVine", "REPEAT", "CLAMP")
            art.vines[index] = vine
        end
        for index, bloom in ipairs(BLOOMS) do
            art.buds[index] = Tex(art, fx.top, "CaseBud", "BLEND", nil, nil, nil, "OVERLAY", 2)
            art.flowers[index] = Tex(art, fx.top, "CaseBlossom", "BLEND", 1, bloom[4] and 0.72 or 0.97, bloom[4] and 0.84 or 0.95, "OVERLAY", 3)
        end
    end,
    Enter = function(fx)
        Mood(fx, { 0.02, 0.045, 0.02 }, { 0.55, 1, 0.45 })
    end,
    Reveal = function(fx)
        return Swing(fx, 0.62, 0.45, 0.45)
    end,
    Update = function(fx, art, dt, left, right)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        -- what's on each gate rides along with it
        local shiftL, shiftR = -(w / 2 - left), w / 2 - right
        if fx.phase == "opening" then
            local fade = 1 - Clamp01((t - 0.95) / 0.15)
            for index, vine in ipairs(VINES) do
                local texture = art.vines[index]
                local length = w * 0.56 * EaseOutCubic((t - vine[3]) / 0.35)
                if length > 1 and fade > 0 then
                    if vine[1] < 0 then
                        texture:SetPoint("LEFT", fx, "LEFT", shiftL, vine[2])
                        texture:SetTexCoord(0, length / 180, 0, 1)
                    else
                        texture:SetPoint("RIGHT", fx, "RIGHT", shiftR, vine[2])
                        texture:SetTexCoord(length / 180, 0, 0, 1)
                    end
                    texture:SetSize(length, 22)
                    texture:SetAlpha(fade)
                    Show(texture)
                else
                    Off(texture)
                end
            end
            for index, bloom in ipairs(BLOOMS) do
                local x = bloom[1] + (bloom[1] < 0 and shiftL or shiftR)
                local grown = EaseOutBack((t - bloom[3]) / 0.12, 2)
                local open = Clamp01((t - bloom[3] - 0.1) / 0.12)
                if grown > 0.05 and fade > 0 then
                    if open < 1 then
                        Put(fx, art.buds[index], x, bloom[2], 12 * grown, 12 * grown, (1 - open) * fade)
                    else
                        Off(art.buds[index])
                    end
                    if open > 0 then
                        local size = 20 * (0.6 + 0.4 * EaseOutBack(open, 1.5))
                        art.flowers[index]:SetRotation(bloom[3] * 10 + t * 0.4)
                        Put(fx, art.flowers[index], x, bloom[2], size, size, open * fade)
                        if Chance(3, dt) then
                            Part(fx, "sparkle", x + Random(-6, 6), bloom[2] + Random(-6, 6), Random(-6, 6), Random(6, 18), Random(0.5, 0.8), Random(3, 5), 1, 0.9, 0.45, 0.9)
                        end
                    else
                        Off(art.flowers[index])
                    end
                else
                    Off(art.buds[index])
                    Off(art.flowers[index])
                end
            end
            -- as the gates part, leaves and petals shake loose
            if t > 0.62 and t < 0.85 and Chance(45, dt) then
                local pink = math.random() < 0.4
                local p = Part(fx, pink and "petal" or "leaf", Random(-w / 2 + 10, w / 2 - 10), Random(-35, 35), Random(-50, 50), Random(-10, 40), Random(0.6, 1.0), Random(7, 10),
                    1, pink and 0.72 or 1, pink and 0.84 or 1)
                if p then
                    p.g, p.grow = -120, 0
                end
            end
        else
            for _, texture in ipairs(art.vines) do
                Off(texture)
            end
            for index in ipairs(BLOOMS) do
                Off(art.buds[index])
                Off(art.flowers[index])
            end
        end
        if fx.phase == "open" and Chance(3, dt) then
            local pink = math.random() < 0.5
            local p = Part(fx, pink and "petal" or "leaf", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), h / 2 - GATE_CORNER, Random(-10, 10), Random(-20, -8), Random(1.4, 2), Random(6, 8),
                1, pink and 0.72 or 1, pink and 0.84 or 1, 0.9)
            if p then
                p.grow = 0
                p.late = true
            end
        end
        MoveReel(fx, fx.phase == "opening" and 70 * Clamp01((t - 0.62) / 0.3) or 70, dt)
        DressCells(fx, 0, false, false, 1.5, 0)
    end,
}))

-- =============================================================================================================
-- Gates that stay where they are, and fade or fall
-- =============================================================================================================

-- A drifting fog layer: tileable, scrolled under its own texture coordinates.
local function FogLayer(art, parent, layer, sub, r, g, b)
    local texture = Tex(art, parent, nil, "BLEND", r, g, b, layer, sub)
    texture:SetTexture(MEDIA .. "CaseFog", "REPEAT", "REPEAT")
    return texture
end

-- How thick a style's fog is: rising, holding, thinning, and the same again as it closes.
local function FogAmount(fx, upFor, clearFrom, clearFor)
    local t = fx.t
    if fx.phase == "opening" then
        return Clamp01(t / upFor) * (1 - Clamp01((t - clearFrom) / clearFor))
    elseif fx.phase == "closing" then
        return Clamp01(t / 0.25) * (1 - Clamp01((t - 0.45) / 0.3))
    end
    return 0
end

-- --- Jade Mist (Mistweaver monk): jade mist rolls over the gates, a jade serpent winds through it, the gates fade -------

local SERPENT = 13 -- body segments behind the head

local function SerpentAt(s, w)
    return -w / 2 - 40 + (w + 80) * s, 22 * sin(s * 2 * pi * 1.2 + 0.5)
end

Register("mistweaver", "Jade Mist", "MONK", 270, StillStyle("mistweaver", {
    openFor = 1.05, closeFor = 0.75,
    Build = function(fx, art)
        art.fogs = { FogLayer(art, fx.top, "OVERLAY", 0, 0.6, 1, 0.85), FogLayer(art, fx.top, "OVERLAY", 0, 0.75, 1, 0.9) }
        art.haze = FogLayer(art, fx.mid, "OVERLAY", 0, 0.6, 1, 0.85)
        art.glow = Tex(art, fx.top, "CaseGlow", "ADD", 0.45, 1, 0.75, "OVERLAY", 1)
        art.body = {}
        for index = 1, SERPENT do
            art.body[index] = Tex(art, fx.top, "CaseSerpentBody", "BLEND", nil, nil, nil, "OVERLAY", 2)
        end
        art.head = Tex(art, fx.top, "CaseSerpentHead", "BLEND", nil, nil, nil, "OVERLAY", 3)
    end,
    Enter = function(fx)
        Mood(fx, { 0.02, 0.05, 0.045 }, { 0.5, 1, 0.8 })
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        DoorsAlpha(fx, Fade(fx, 0.35, 0.55, 0.2, 0.4))
        -- two layers of mist drifting across each other over the gates
        local fog = FogAmount(fx, 0.3, 0.62, 0.38)
        Drift(fx, art.fogs[1], dt, 0.12, 0.02, 0, 0, w, h, fog * 0.6)
        Drift(fx, art.fogs[2], dt, -0.08, -0.03, 0, 0, w * 1.1, h * 1.1, fog * 0.45)
        -- the serpent: head first, its body following the same winding path
        local s = (t - 0.1) / 0.75
        if fx.phase == "opening" and s > -0.05 and s < 1.6 then
            local hx, hy = SerpentAt(s, w)
            local ax, ay = SerpentAt(s + 0.01, w)
            PutTurned(fx, art.head, hx, hy, 34, atan2(ay - hy, ax - hx), 1)
            Put(fx, art.glow, hx, hy, 70, 60, 0.45)
            for index, segment in ipairs(art.body) do
                local sk = s - 0.03 * index
                local bx, by = SerpentAt(sk, w)
                local size = 21 - 1.05 * index
                Put(fx, segment, bx, by, size, size, 1 - index * 0.03)
            end
            if Chance(50, dt) then
                local p = Part(fx, "sparkle", hx - 10, hy + Random(-6, 6), Random(-20, 0), Random(-8, 8), Random(0.4, 0.6), Random(4, 6), 0.5, 1, 0.8)
                if p then
                    p.grow = -0.5
                end
            end
        else
            Off(art.head)
            Off(art.glow)
            for _, segment in ipairs(art.body) do
                Off(segment)
            end
        end
        -- a little mist stays, drifting over the reel
        local haze = fx.phase == "open" and 0.16 or fx.phase == "opening" and 0.16 * Clamp01((t - 0.6) / 0.4) or 0.16 * (1 - Clamp01(t / 0.3))
        Drift(fx, art.haze, dt, 0.05, 0.01, 0, 0, fx.windowWidth, h - 2 * GATE_CORNER, haze)
        MoveReel(fx, 55, dt)
        DressCells(fx, 0, false, false, 2, 0)
    end,
}))

-- --- Emerald Dream (Preservation evoker): emerald blossoms open, gold pollen drifts, the gates fade like a dream ---------

local BLOSSOMS = { { -72, 26, 0.0 }, { -20, -24, 0.08 }, { 34, 30, 0.14 }, { 78, -20, 0.2 }, { -50, -34, 0.26 }, { 6, 4, 0.3 } }

Register("preservation", "Emerald Dream", "EVOKER", 1468, StillStyle("preservation", {
    openFor = 1.05, closeFor = 0.7,
    Build = function(fx, art)
        art.fog = FogLayer(art, fx.top, "OVERLAY", 0, 0.45, 1, 0.65)
        art.dream = Tex(art, fx.top, "CaseGlow", "ADD", 0.3, 1, 0.55, "OVERLAY", 0)
        art.glows, art.blossoms = {}, {}
        for index in ipairs(BLOSSOMS) do
            art.glows[index] = Tex(art, fx.top, "CaseGlow", "ADD", 0.3, 1, 0.5, "OVERLAY", 1)
            art.blossoms[index] = Tex(art, fx.top, "CaseBlossom", "BLEND", 0.55, 1, 0.7, "OVERLAY", 2)
        end
    end,
    Enter = function(fx)
        Mood(fx, { 0.02, 0.05, 0.04 }, { 0.4, 1, 0.65 })
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        DoorsAlpha(fx, Fade(fx, 0.4, 0.6, 0.1, 0.5))
        local bloom, fade = 0, 0
        if fx.phase == "opening" then
            bloom, fade = 1, 1 - Clamp01((t - 0.65) / 0.35)
            Put(fx, art.dream, 0, 0, w * 1.4, h * 1.4, sin(pi * Clamp01((t - 0.3) / 0.75)) * 0.6)
            -- the gates turn dreamlike green before they fade
            local dream = Clamp01(t / 0.4)
            K.FaceTint(fx, 1 - 0.3 * dream, 1, 1 - 0.25 * dream)
        elseif fx.phase == "closing" then
            -- the blossoms close up over the gates as they come back
            bloom, fade = 1 - Clamp01((t - 0.35) / 0.3), sin(pi * Clamp01(t / 0.7))
            Off(art.dream)
        else
            Off(art.dream)
        end
        Drift(fx, art.fog, dt, 0.05, 0.02, 0, 0, w, h, FogAmount(fx, 0.35, 0.6, 0.4) * 0.45)
        for index, blossom in ipairs(BLOSSOMS) do
            local open = fx.phase == "opening" and EaseOutBack((t - blossom[3]) / 0.3, 1.6) or bloom
            local size = 24 * open
            if size > 0.5 and fade > 0 then
                art.blossoms[index]:SetRotation(index * 1.3 + (fx.phase == "opening" and t * 0.6 or 0))
                Put(fx, art.blossoms[index], blossom[1], blossom[2], size, size, fade)
                Put(fx, art.glows[index], blossom[1], blossom[2], size * 2.6, size * 2.6, fade * 0.6)
            else
                Off(art.blossoms[index])
                Off(art.glows[index])
            end
        end
        if fx.phase ~= "closing" and Chance(fx.phase == "open" and 6 or 18, dt) then
            local p = Part(fx, "sparkle", Random(-w / 2 + 10, w / 2 - 10), Random(-h / 2 + 15, h / 2 - 15), Random(-8, 8), Random(6, 20), Random(0.8, 1.3), Random(3, 5), 1, 0.85, 0.4, 0.9)
            if p then
                p.grow = -0.3
            end
        end
        if fx.phase == "opening" and t > 0.65 and Chance(20, dt) then
            local p = Part(fx, "petal", Random(-w / 2 + 10, w / 2 - 10), Random(-30, 30), Random(-20, 20), Random(10, 30), Random(0.7, 1), Random(6, 8), 0.55, 1, 0.7)
            if p then
                p.grow = -0.3
            end
        end
        MoveReel(fx, 60, dt)
        DressCells(fx, 0, false, false, 2, 0)
    end,
}))

-- --- Shadow Fade (Subtlety rogue): the gates blur into shadowy doubles and smoke; the items come in from the dark ------

Register("subtlety", "Shadow Fade", "ROGUE", 261, StillStyle("subtlety", {
    openFor = 1.0, closeFor = 0.75,
    Build = function(fx, art)
        art.doubles = { Tex(art, fx.top, nil, "BLEND", 0.55, 0.45, 0.75, "OVERLAY", 0), Tex(art, fx.top, nil, "BLEND", 0.55, 0.45, 0.75, "OVERLAY", 0) }
        art.smoke = FogLayer(art, fx.top, "OVERLAY", 1, 0.05, 0.035, 0.07)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.015, 0.012, 0.02 }, { 0.6, 0.4, 0.95 })
        FadeIcons(fx, 0)
        local atlas = K.FaceAtlas(fx.owner)
        for _, double in ipairs(art.doubles) do
            if double.SetAtlas then
                double:SetAtlas(atlas)
                double:SetVertexColor(0.55, 0.45, 0.75)
            end
        end
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        DoorsAlpha(fx, Fade(fx, 0.18, 0.4, 0.3, 0.4))
        if fx.phase == "opening" then
            -- the gates darken, and shadowy doubles slip off them to either side
            local shade = Clamp01(t / 0.2)
            K.FaceTint(fx, 1 - 0.45 * shade, 1 - 0.5 * shade, 1 - 0.3 * shade, shade > 0.5)
            local slip = Clamp01((t - 0.05) / 0.35)
            for index, double in ipairs(art.doubles) do
                local side = index == 1 and -1 or 1
                if slip > 0 and slip < 1 then
                    Put(fx, double, side * 16 * EaseOutCubic(slip), 2 * side, w, h, 0.45 * (1 - slip))
                else
                    Off(double)
                end
            end
            FadeIcons(fx, Clamp01((t - 0.4) / 0.6) * 1.6)
        elseif fx.phase == "open" then
            if fx.entered then
                FadeIcons(fx, 2)
            end
            if Chance(3, dt) then
                local p = Part(fx, "sparkle", Random(-fx.windowWidth / 2 + 6, fx.windowWidth / 2 - 6), Random(-30, 30), 0, 0, Random(0.3, 0.5), Random(5, 7), 0.6, 0.4, 0.95, 0.8)
                if p then
                    p.grow = -0.6
                end
            end
        else
            FadeIcons(fx, (1 - Clamp01(t / 0.35)) * 1.6)
            for _, double in ipairs(art.doubles) do
                Off(double)
            end
        end
        -- smoke boils up over the gates as they go, and again as they come back
        local smoke = 0
        if fx.phase == "opening" then
            smoke = Clamp01(t / 0.2) * (1 - Clamp01((t - 0.45) / 0.35))
        elseif fx.phase == "closing" then
            smoke = sin(pi * Clamp01((t - 0.1) / 0.55))
        end
        Drift(fx, art.smoke, dt, 0.1, 0.06, 0, 0, w, h, smoke * 0.85)
        if smoke > 0.2 and Chance(20, dt) then
            local a = Random(0, pi * 2)
            Smoke(fx, cos(a) * Random(0, 60), sin(a) * Random(0, 30), cos(a) * Random(20, 50), sin(a) * Random(10, 30) + 10, Random(0.8, 1.2), Random(40, 60), 0.85, 0.06, 0.045, 0.09)
        end
        MoveReel(fx, 60, dt)
        DressCells(fx, 0, false, false, 0, 0)
    end,
    Rest = function(fx)
        for _, cell in ipairs(fx.cells) do
            cell.icon:SetAlpha(1)
        end
    end,
}))

-- --- Barrier (Discipline priest): a shimmering dome covers the slot, cracks, and shatters, taking the gates with it -------

local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- The dome: its rim, a faint fill, and a shimmering lattice inside it, `grow` times its size.
local function Dome(fx, art, grow, alpha)
    local dw, dh = fx.slotWidth * 0.98 * grow, fx.slotHeight * 1.1 * grow
    local shimmer = 0.85 + 0.15 * sin(GetTime() * 30)
    Put(fx, art.dome, 0, 0, dw, dh, alpha * shimmer)
    Put(fx, art.fill, 0, 0, dw * 0.95, dh * 0.95, alpha * 0.2)
    art.hex:SetRotation(GetTime() * 0.2)
    art.hexMask:SetPoint("CENTER", fx, "CENTER", 0, 0)
    art.hexMask:SetSize(dw * 0.96, dh * 0.96)
    Put(fx, art.hex, 0, 0, dw * 1.2, dw * 1.2, alpha * 0.35 * shimmer)
end

Register("discipline", "Barrier", "PRIEST", 256, StillStyle("discipline", {
    openFor = 0.85, closeFor = 0.65,
    Build = function(fx, art)
        art.fill = Tex(art, fx.top, "CaseDisc", "ADD", 1, 0.9, 0.6, "OVERLAY", 0)
        art.hex = Tex(art, fx.top, "CaseHex", "ADD", 1, 0.88, 0.55, "OVERLAY", 1)
        art.hexMask = fx.top:CreateMaskTexture()
        art.hexMask:SetTexture(CIRCLE, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        art.hex:AddMaskTexture(art.hexMask)
        art.dome = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.92, 0.62, "OVERLAY", 2)
        art.cracks = Tex(art, fx.top, "CaseCracks", "ADD", 1, 0.9, 0.5, "OVERLAY", 3)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.95, 0.8, "OVERLAY", 4)
        art.shell = Tex(art, fx.mid, "CaseRing", "ADD", 1, 0.92, 0.62)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.05, 0.045, 0.03 }, { 1, 0.9, 0.55 })
        art.popAt = nil
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "opening" then
            if t < 0.58 then
                Dome(fx, art, EaseOutBack(t / 0.3, 1.5), 1)
                K.FaceTint(fx, 1, 1 - 0.05 * Clamp01(t / 0.3), 1 - 0.2 * Clamp01(t / 0.3))
                local q = EaseOutCubic((t - 0.34) / 0.2)
                if q > 0 then
                    Put(fx, art.cracks, 0, 0, w * (0.4 + 0.6 * q), h * (0.4 + 0.6 * q), q)
                else
                    Off(art.cracks)
                end
                DoorsAlpha(fx, 1)
            else
                if not art.popAt then
                    art.popAt = GetTime()
                    Off(art.dome)
                    Off(art.fill)
                    Off(art.hex)
                    Off(art.cracks)
                    fx.shake = 0.8
                    Burst(fx, "sparkle", 10, 0, 0, 70, 170, 0.5, 8, 1, 0.92, 0.6)
                    Chips(fx, 12, 0, 0, 80, 200, 60, 1, 0.85, 0.45)
                end
                DoorsAlpha(fx, 1 - Clamp01((t - 0.58) / 0.12))
            end
        elseif fx.phase == "open" then
            DoorsAlpha(fx, 0)
            Put(fx, art.shell, 0, 0, fx.windowWidth * 1.1, (h - 2 * GATE_CORNER) * 1.3, 0.12 + 0.05 * sin(GetTime() * 2))
        else
            -- the dome forms again, the gates come back under it, and it fades
            Off(art.shell)
            Dome(fx, art, 1.4 - 0.4 * EaseOutCubic(t / 0.3), Clamp01(t / 0.15) * (1 - Clamp01((t - 0.45) / 0.2)))
            DoorsAlpha(fx, Clamp01((t - 0.2) / 0.25))
        end
        Flash(fx, art.flash, art.popAt, 0.25, 0, 0, w * 1.1, h * 1.2, 1)
        MoveReel(fx, fx.phase == "opening" and (t < 0.58 and 0 or 70) or 70, dt)
        DressCells(fx, 0, false, false, 1, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Shield Slam (Protection warrior): a shield slams into the slot; the gates crack, buckle and fall in --------------------

Register("protwarrior", "Shield Slam", "WARRIOR", 73, StillStyle("protwarrior", {
    faceMode = "squash", openFor = 0.95, closeFor = 0.6,
    Build = function(fx, art)
        art.ghosts = { Tex(art, fx.top, "CaseShieldKite", "BLEND", nil, nil, nil, "OVERLAY", 2), Tex(art, fx.top, "CaseShieldKite", "BLEND", nil, nil, nil, "OVERLAY", 2) }
        art.shield = Tex(art, fx.top, "CaseShieldKite", "BLEND", nil, nil, nil, "OVERLAY", 3)
        art.cracks = Tex(art, fx.top, "CaseCracks", "BLEND", 0.1, 0.08, 0.06, "OVERLAY", 1)
        art.ring = Tex(art, fx.top, "CaseRing", "ADD", 1, 0.9, 0.75, "OVERLAY", 4)
        art.flash = Tex(art, fx.top, "CaseGlow", "ADD", 1, 0.92, 0.8, "OVERLAY", 5)
    end,
    Enter = function(fx, art)
        Mood(fx, { 0.04, 0.035, 0.035 }, { 0.9, 0.3, 0.25 })
        art.slamAt = nil
    end,
    Update = function(fx, art, dt)
        local t = fx.t
        local w, h = fx.slotWidth, fx.slotHeight
        local scale, drop, alpha = 1, 0, 1 -- the gates' faces: how big, how far fallen, how visible
        if fx.phase == "opening" then
            if t < 0.16 then
                -- the shield rushes in, blurred by its speed
                local k = EaseInCubic(t / 0.16)
                local size = 300 - 214 * k
                Put(fx, art.shield, 0, 0, size, size, Clamp01(k * 2))
                for index, ghost in ipairs(art.ghosts) do
                    local lag = EaseInCubic(max(0, t - 0.025 * index) / 0.16)
                    local gsize = 300 - 214 * lag
                    Put(fx, ghost, 0, 0, gsize, gsize, 0.3 / index * Clamp01(k * 2))
                end
            else
                for _, ghost in ipairs(art.ghosts) do
                    Off(ghost)
                end
                if not art.slamAt then
                    art.slamAt = GetTime()
                    fx.shake = 2.6
                    Chips(fx, 10, 0, 0, 80, 200, 30)
                    for n = 0, 7 do
                        local a = n / 8 * pi * 2
                        Smoke(fx, cos(a) * 40, sin(a) * 25, cos(a) * Random(50, 90), sin(a) * Random(30, 60), Random(0.6, 0.9), Random(34, 46), 0.6, 0.62, 0.56, 0.5)
                    end
                end
                -- the shield bounces off and fades
                local bounce = 1 + 0.12 * sin(pi * Clamp01((t - 0.16) / 0.18))
                Put(fx, art.shield, 0, 0, 86 * bounce, 86 * bounce, 1 - Clamp01((t - 0.36) / 0.2))
                -- the gates buckle, then fall in: smaller, lower, fading
                local buckle = sin(pi * Clamp01((t - 0.16) / 0.15))
                local fall = EaseInCubic((t - 0.33) / 0.45)
                scale = 1 - 0.06 * buckle - 0.45 * fall
                drop = 70 * fall
                alpha = 1 - Clamp01((t - 0.55) / 0.25)
                K.FaceTint(fx, 1 - 0.25 * fall, 1 - 0.25 * fall, 1 - 0.22 * fall)
            end
            -- the cracks ride on the gates
            if art.slamAt then
                local grow = 0.5 + 0.5 * EaseOutCubic((t - 0.16) / 0.1)
                Put(fx, art.cracks, 0, -drop, w * scale * grow, h * scale * grow, 0.9 * alpha)
            end
        else
            Off(art.shield)
            for _, ghost in ipairs(art.ghosts) do
                Off(ghost)
            end
            Off(art.cracks)
            if fx.phase == "open" then
                alpha = 0
            else
                local k = EaseOutCubic(t / 0.5)
                scale, drop, alpha = 0.55 + 0.45 * k, 70 * (1 - k), Clamp01(t / 0.25)
                if t >= 0.5 and not fx.flags.thud then
                    fx.flags.thud = true
                    fx.shake = 1.2
                    for side = -1, 1, 2 do
                        Smoke(fx, side * 70, -h / 2 + 10, side * Random(20, 40), Random(5, 20), 0.6, 34, 0.5, 0.62, 0.56, 0.5)
                    end
                end
            end
        end
        local top, bottom = fx.topDoor.face, fx.bottomDoor.face
        top:SetSize(w * scale, h * scale)
        top:SetPoint("CENTER", fx, "CENTER", 0, -drop)
        bottom:SetSize(w * scale, h * scale)
        bottom:SetPoint("CENTER", fx, "CENTER", 0, -drop)
        DoorsAlpha(fx, alpha)
        Ring(fx, art.ring, art.slamAt, 0.35, 0, 0, 60, 300, 0.62, 0.9)
        Flash(fx, art.flash, art.slamAt, 0.18, 0, 0, w, h, 0.8)
        MoveReel(fx, fx.phase == "opening" and (t < 0.33 and 0 or 85) or 85, dt)
        DressCells(fx, 0.1, false, false, 0, 0)
        K.Shake(fx, dt)
    end,
}))

-- --- Runic Frost (Frost death knight): runes glow on iced-over gates; the ice cracks along them and shatters -------------

local frostStyle = K.STYLE.frost

Register("frostdk", "Runic Frost", "DEATHKNIGHT", 251, {
    openFor = 1.05,
    closeFor = frostStyle.closeFor,
    Enter = function(fx)
        frostStyle.Enter(fx)
        local art = Art(fx, "frostdk", function(_, a)
            a.runes = Tex(a, fx.top, "CaseRunes", "ADD", 0.55, 0.82, 1, "OVERLAY", 2)
            a.outer = Tex(a, fx.top, "CaseRunes", "ADD", 0.7, 0.88, 1, "OVERLAY", 2)
            a.behind = Tex(a, fx.window, "CaseRunes", "ADD", 0.55, 0.82, 1, "BORDER", 1)
        end)
        for _, s in ipairs(fx.frostArt.shards) do
            s.texture:SetVertexColor(0.72, 0.86, 1)
        end
        Off(art.runes)
    end,
    Update = function(fx, dt)
        local art = fx.styleArt.frostdk
        local frost = fx.frostArt
        local t, flags = fx.t, fx.flags
        local w, h = fx.slotWidth, fx.slotHeight
        if fx.phase == "closing" then
            Off(art.runes)
            Off(art.outer)
            art.behind:SetAlpha(0.2 * (1 - Clamp01(t / 0.3)))
            frostStyle.Update(fx, dt)
            return
        end
        local speed = 80
        if fx.phase == "opening" then
            if t < 0.62 then
                frost.plate:SetAlpha(Clamp01(t / 0.22))
                -- the runes light up on the ice, brighter and brighter
                local glow = Clamp01((t - 0.15) / 0.2)
                local bright = Clamp01((t - 0.35) / 0.25)
                art.runes:SetRotation(t * 0.8)
                art.outer:SetRotation(-t * 0.5)
                Put(fx, art.runes, 0, 0, 100, 100, glow * (0.6 + 0.4 * bright))
                Put(fx, art.outer, 0, 0, 150, 150, bright * 0.5)
                local q = EaseOutCubic((t - 0.45) / 0.15)
                if q > 0 then
                    frost.cracks:SetSize(w * (0.4 + 0.6 * q), h * (0.4 + 0.6 * q))
                    frost.cracks:SetAlpha(q)
                    frost.cracks:Show()
                end
                speed = 0
            else
                if not flags.shattered then
                    flags.shattered = true
                    frost.plate:Hide()
                    frost.cracks:Hide()
                    K.Doors(fx, 0, 0)
                    K.Shatter(fx, frost)
                    Burst(fx, "sparkle", 6, 0, 0, 60, 140, 0.5, 8, 0.55, 0.82, 1)
                end
                local fade = 1 - Clamp01((t - 0.62) / 0.2)
                art.runes:SetAlpha(fade)
                art.outer:SetAlpha(fade * 0.5)
                speed = 80 * EaseOutCubic((t - 0.62) / 0.4)
            end
        else
            Off(art.runes)
            Off(art.outer)
        end
        -- a faint rune ring turns behind the reel
        art.behind:SetRotation(GetTime() * 0.4)
        Put(fx, art.behind, 0, 0, 96, 96, fx.phase == "open" and 0.2 or 0.2 * Clamp01((t - 0.62) / 0.3))
        K.FlyShards(fx, frost, dt)
        MoveReel(fx, speed, dt)
    end,
    Rest = function(fx)
        local art = fx.styleArt and fx.styleArt.frostdk
        if art then
            for _, region in ipairs(art.list) do
                region:Hide()
                region.bgvOn = false
            end
        end
        if fx.frostArt then
            for _, s in ipairs(fx.frostArt.shards) do
                s.texture:SetVertexColor(1, 1, 1)
            end
        end
        frostStyle.Rest(fx)
    end,
})
