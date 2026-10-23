local _, BGV = ...

-- Skeleton previews for the settings page: pointing at an option shows a small sketch of the
-- addon's UI with the place that option changes lit in the accent color, like a tooltip. Pointing
-- changes nothing. The sketch is flat rectangles, discs and short labels drawn on one shared card,
-- built the first time it shows and drawn again only when the pointer rests on an option.
-- The opening animations are shown playing (Case.ShowPreview) rather than sketched.

BGV.SettingsPreview = {}

local Preview = BGV.SettingsPreview
local Utils = BGV.Utils
local L = BGV.L

local WHITE = "Interface\\Buttons\\WHITE8X8"
local CIRCLE_MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local CURSOR = "Interface\\CURSOR\\Point"

local CANVAS_W, CANVAS_H = 300, 180
local PAD = 12
local BAR_H = 3
local DELAY = 0.18 -- a short rest on an option before its sketch shows, like a tooltip

-- The sketch's grays (the rest of the UI, for orientation) and the card's.
local SK_FILL = { 0.098, 0.098, 0.106 }
local SK_EDGE = { 0.18, 0.184, 0.2 }
local SK_RAISED = { 0.149, 0.149, 0.161 }
local SK_LINE = { 0.231, 0.231, 0.251 }
local CANVAS_BG = { 0.047, 0.047, 0.051 }
local CARD_BG = { 0.067, 0.067, 0.071 }
local CARD_EDGE = { 0.173, 0.176, 0.192 }
local LABEL = { 0.725, 0.71, 0.67 }
local TIER_ORDER = { "S", "A", "B", "C" }

local card, canvas
local hl = { 0.85, 0.65, 0.2 } -- the lit color of the sketch being drawn
local litFill = { 0.28, 0.23, 0.11 } -- the lit parts' fill: the lit color, dimmed over the dark
local ox, oy, sc = 0, 0, 1 -- where the window being drawn sits on the canvas, and its scale
local page -- the settings page: the card lines up with its right edge
local token = 0
local playing = false -- the card holds a playing opening (Case.ShowPreview)
local shownFor -- the option the card shows, while it shows: { owner, key, title }

-- Sheets: child frames of the canvas, each over the one before. The sketch's own parts go on the
-- first; each window drawn over it (Window) on the next, so it covers what's under it, text too;
-- the pointer on the last. Each sheet keeps its own pools of textures, discs and labels, made once
-- and reused.
local SHEETS = 4
local sheets = {}
local sheet -- the sheet being drawn on
local nextSheet = 2 -- the sheet the next window takes
local bare = false -- drawing small, for Preview.Draw: no labels (too small to read)

local function SetLitColor(color)
    hl = color
    litFill[1], litFill[2], litFill[3] = color[1] * 0.26 + 0.058, color[2] * 0.26 + 0.058, color[3] * 0.26 + 0.058
end

-- A frame metric that's safe to do sums with (the game can answer with a secret value in
-- restricted moments), else nil.
local function Metric(value)
    return Utils.IsUsableNumber(value) and value or nil
end

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function UseSheet(index)
    index = math.min(SHEETS, index)
    local found = sheets[index]
    if not found then
        local frame = CreateFrame("Frame", nil, canvas)
        frame:SetAllPoints(canvas)
        frame:SetFrameLevel(canvas:GetFrameLevel() + index)
        found = { frame = frame, textures = {}, discs = {}, labels = {}, usedTextures = 0, usedDiscs = 0, usedLabels = 0 }
        sheets[index] = found
    end
    sheet = found
end

-- Drawing --------------------------------------------------------------------------------------
-- Coordinates are the canvas's, from its top left, y down; a window drawn inside another sits at
-- (ox, oy) at scale `sc`. Sublevels (`z`) put a window's parts over the window.

local function NextTexture()
    local index = sheet.usedTextures + 1
    local texture = sheet.textures[index]
    if not texture then
        texture = sheet.frame:CreateTexture(nil, "ARTWORK")
        sheet.textures[index] = texture
    end
    sheet.usedTextures = index
    texture:ClearAllPoints()
    texture:SetTexture(WHITE)
    texture:SetAlpha(1)
    texture:Show()
    return texture
end

-- Draw sublevels run from -8 to 7.
local function Sublevel(z)
    return math.max(-8, math.min(7, z or 0))
end

local function Fill(x, y, w, h, color, z, alpha)
    local texture = NextTexture()
    texture:SetDrawLayer("ARTWORK", Sublevel(z))
    texture:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", x, -y)
    texture:SetSize(math.max(1, w), math.max(1, h))
    return texture
end

local function Edges(x, y, w, h, color, z)
    Fill(x, y, w, 1, color, z)
    Fill(x, y + h - 1, w, 1, color, z)
    Fill(x, y, 1, h, color, z)
    Fill(x + w - 1, y, 1, h, color, z)
end

-- A rectangle. kind: "sk" (a window or slot, outlined), "raised", "line", "lit" (the place this
-- option changes, outlined in the lit color), "litfill" (solid lit color), or a color.
local function Rect(x, y, w, h, kind, z)
    x, y, w, h = ox + x * sc, oy + y * sc, w * sc, h * sc
    z = z or 1
    if kind == "sk" then
        Fill(x, y, w, h, SK_FILL, z)
        Edges(x, y, w, h, SK_EDGE, z + 1)
    elseif kind == "lit" then
        Fill(x, y, w, h, litFill, z)
        Edges(x, y, w, h, hl, z + 1)
    elseif kind == "raised" then
        Fill(x, y, w, h, SK_RAISED, z)
    elseif kind == "line" then
        Fill(x, y, w, h, SK_LINE, z)
    elseif kind == "litfill" then
        Fill(x, y, w, h, hl, z)
    else
        Fill(x, y, w, h, kind, z)
    end
end

local function Disc(cx, cy, r, color, z, alpha)
    local index = sheet.usedDiscs + 1
    local disc = sheet.discs[index]
    if not disc then
        disc = sheet.frame:CreateTexture(nil, "ARTWORK")
        disc:SetTexture(WHITE)
        local mask = sheet.frame:CreateMaskTexture()
        mask:SetTexture(CIRCLE_MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
        mask:SetAllPoints(disc)
        disc:AddMaskTexture(mask)
        sheet.discs[index] = disc
    end
    sheet.usedDiscs = index
    cx, cy, r = ox + cx * sc, oy + cy * sc, r * sc
    disc:ClearAllPoints()
    disc:SetDrawLayer("ARTWORK", Sublevel(z or 1))
    disc:SetColorTexture(color[1], color[2], color[3], alpha or 1)
    disc:SetSize(math.max(1, r * 2), math.max(1, r * 2))
    disc:SetPoint("CENTER", canvas, "TOPLEFT", cx, -cy)
    disc:Show()
end

-- A round part, kinds as for Rect.
local function Round(cx, cy, r, kind, z, alpha)
    z = z or 1
    if kind == "sk" then
        Disc(cx, cy, r, SK_EDGE, z, alpha)
        Disc(cx, cy, r - 1 / sc, SK_FILL, z + 1, alpha)
    elseif kind == "lit" then
        Disc(cx, cy, r, hl, z, alpha)
        Disc(cx, cy, r - 1.5 / sc, litFill, z + 1, alpha)
    elseif kind == "raised" then
        Disc(cx, cy, r, SK_RAISED, z, alpha)
    elseif kind == "line" then
        Disc(cx, cy, r, SK_LINE, z, alpha)
    elseif kind == "litfill" then
        Disc(cx, cy, r, hl, z, alpha)
    else
        Disc(cx, cy, r, kind, z, alpha)
    end
end

-- A straight line from one point to another (arrows, crosses), in canvas coordinates: one bar
-- when it runs straight across or down, else a row of small squares (a texture turns cleanly only
-- when it's square, so a turned bar would stretch instead).
local function Bar(x1, y1, x2, y2, thickness, color, z)
    thickness = thickness or 1.5
    z = z or 5
    local dx, dy = x2 - x1, y2 - y1
    if dy == 0 then
        Fill(math.min(x1, x2), y1 - thickness / 2, math.max(math.abs(dx), thickness), thickness, color, z)
        return
    elseif dx == 0 then
        Fill(x1 - thickness / 2, math.min(y1, y2), thickness, math.max(math.abs(dy), thickness), color, z)
        return
    end
    local steps = math.max(1, math.floor(math.sqrt(dx * dx + dy * dy) / thickness + 0.5))
    for step = 0, steps do
        local t = step / steps
        Fill(x1 + dx * t - thickness / 2, y1 + dy * t - thickness / 2, thickness, thickness, color, z)
    end
end

local function Arrow(x1, y1, x2, y2, color)
    Bar(x1, y1, x2, y2, 1.5, color)
    local angle = math.atan2(y2 - y1, x2 - x1)
    for _, turn in ipairs({ 2.6, -2.6 }) do
        Bar(x2, y2, x2 + math.cos(angle + turn) * 6, y2 + math.sin(angle + turn) * 6, 1.5, color)
    end
end

-- Dots along a curve from (x1, y1) to (x2, y2), bending through (bx, by).
local function Dots(x1, y1, bx, by, x2, y2, color)
    for step = 0, 16 do
        local t = step / 16
        local u = 1 - t
        local x = u * u * x1 + 2 * u * t * bx + t * t * x2
        local y = u * u * y1 + 2 * u * t * by + t * t * y2
        Fill(x - 1, y - 1, 2, 2, color, 5)
    end
end

-- A label in the sketch's small fixed font, `width` wide in the window's units (its box's
-- inside): a longer one is cut with "...", or wraps onto more lines with `wrap`. point: "LEFT"
-- (starts at x), "CENTER", or "TOPLEFT" (for a wrapping one).
local function Label(x, y, text, point, color, width, wrap)
    if bare then
        return
    end
    local index = sheet.usedLabels + 1
    local label = sheet.labels[index]
    if not label then
        label = Utils.FontString(sheet.frame, "OVERLAY", "Sketch")
        sheet.labels[index] = label
    end
    sheet.usedLabels = index
    label:ClearAllPoints()
    label:SetWordWrap(wrap and true or false)
    label:SetJustifyV("TOP")
    label:SetWidth(width and math.max(1, width * sc) or 0)
    label:SetJustifyH(point == "CENTER" and "CENTER" or "LEFT")
    label:SetText(text)
    color = color or LABEL
    label:SetTextColor(color[1], color[2], color[3])
    label:SetPoint(point or "LEFT", canvas, "TOPLEFT", ox + x * sc, -(oy + y * sc))
    label:Show()
    return label
end

-- The pointer, over everything.
local function Cursor(x, y)
    local current = sheet
    UseSheet(SHEETS)
    local texture = NextTexture()
    texture:SetDrawLayer("OVERLAY", 7)
    texture:SetTexture(CURSOR)
    texture:SetSize(16, 16)
    texture:SetPoint("TOPLEFT", canvas, "TOPLEFT", x - 2, -(y - 1))
    sheet = current
end

-- Draws `draw` as a window placed at (x, y) on the canvas at `scale`, on a sheet of its own over
-- what's drawn before it.
local function Window(x, y, scale, draw, options)
    local px, py, ps, current = ox, oy, sc, sheet
    ox, oy, sc = x, y, scale
    UseSheet(nextSheet)
    nextSheet = math.min(SHEETS - 1, nextSheet + 1)
    draw(options or {})
    ox, oy, sc, sheet = px, py, ps, current
end

local function Clear()
    for _, each in ipairs(sheets) do
        for index = 1, each.usedTextures do
            each.textures[index]:Hide()
        end
        for index = 1, each.usedDiscs do
            each.discs[index]:Hide()
        end
        for index = 1, each.usedLabels do
            each.labels[index]:Hide()
        end
        each.usedTextures, each.usedDiscs, each.usedLabels = 0, 0, 0
    end
    ox, oy, sc = 0, 0, 1
    nextSheet = 2
    UseSheet(1)
end

-- The addon's windows, sketched --------------------------------------------------------------

local SLOT_X = { 110, 168, 226 }
local ROW_Y = { 30, 70, 110 }

-- The Great Vault: its title, the loot spec button, three rows of a label, art and three slots,
-- and Collect. o.slots / o.done: slots lit / completed, keyed "row slot" from "11".
local function Vault(o)
    Rect(0, 0, 284, 164, "sk", 0)
    Label(142, 11, L["Great Vault"], "CENTER", nil, 120)
    Rect(96, 19, 92, 3, "line", 2)
    Rect(22, 10, 42, 9, o.spec and "lit" or "raised", 2)
    for row, y in ipairs(ROW_Y) do
        Rect(12, y + 12, 30, 5, o.text and "litfill" or "line", 2)
        Rect(46, y, 56, 34, "raised", 1)
        for slot, x in ipairs(SLOT_X) do
            local key = row .. slot
            Rect(x, y, 52, 34, (o.slots and o.slots[key]) and "lit" or "sk", 1)
            if o.done and o.done[key] then
                if o.faces then
                    -- a frown: two eyes and a mouth turned down
                    Round(x + 20, y + 13, 1.8, "litfill", 4)
                    Round(x + 32, y + 13, 1.8, "litfill", 4)
                    Rect(x + 19, y + 24, 3, 2, "litfill", 4)
                    Rect(x + 22, y + 22, 8, 2, "litfill", 4)
                    Rect(x + 30, y + 24, 3, 2, "litfill", 4)
                elseif o.text then
                    Rect(x + 10, y + 10, 32, 3, "litfill", 4)
                    Rect(x + 14, y + 16, 24, 3, "litfill", 4)
                    Rect(x + 8, y + 22, 36, 3, "litfill", 4)
                else
                    Rect(x + 10, y + 12, 32, 3, "line", 4)
                    Rect(x + 8, y + 19, 36, 3, "line", 4)
                end
            end
        end
    end
    Rect(104, 150, 76, 9, o.collect and "lit" or "raised", 2)
    if o.reel then
        -- the first slot open: its gates parted, a reel of items inside
        local x, y = SLOT_X[1], ROW_Y[1]
        Rect(x - 6, y, 10, 34, "lit", 4)
        Rect(x + 48, y, 10, 34, "lit", 4)
        local back = BGV.Case and BGV.Case.TIER_BACK
        for index, tier in ipairs(TIER_ORDER) do
            local color = (o.tiers and back and back[tier]) or SK_LINE
            Rect(x + 6 + (index - 1) * 10, y + 10, 8, 14, color, 4)
        end
    end
end

-- The loot table: its title, loot spec button, header, and item rows. o.w, o.h: its size.
local function LootTable(o)
    local w, h = o.w or 128, o.h or 164
    Rect(0, 0, w, h, o.lit and "lit" or "sk", 0)
    Label(7, 9, L["Loot table"], "LEFT", nil, w - 54)
    Rect(w - 44, 5, 28, 8, o.spec and "lit" or "raised", 2)
    Rect(6, 20, w - 12, 8, o.accent and "litfill" or "raised", 2)
    local tierX = w - 26
    if o.tiers then
        Rect(tierX - 3, 18, 18, h - 24, "lit", 2)
    end
    local back = BGV.Case and BGV.Case.TIER_BACK
    for index = 1, 9 do
        local y = 33 + (index - 1) * 12
        if y + 8 > h - 4 then
            break
        end
        Rect(8, y, 8, 8, "raised", 3)
        Rect(20, y + 2, w - 60 - ((index - 1) % 3) * 10, 3, o.text and "litfill" or "line", 3)
        if o.tiers and back then
            Rect(tierX, y, 12, 8, back[TIER_ORDER[(index - 1) % #TIER_ORDER + 1]], 4)
        else
            Rect(tierX, y + 2, 10, 3, "line", 3)
        end
    end
end

-- The minimap popup: the addon's name, this week's slots, the click list.
local POPUP_W = 136

local function Popup(o)
    Rect(0, 0, POPUP_W, 140, o.lit and "lit" or "sk", 0)
    Round(13, 13, 7, "raised", 2)
    Label(25, 10, "Better Great Vault", "LEFT", o.text and hl or nil, POPUP_W - 29)
    Rect(25, 17, 40, 3, "line", 2)
    Rect(0, 26, POPUP_W, 1, o.accent and "litfill" or "line", 2)
    if o.week then
        Rect(6, 31, POPUP_W - 12, 50, "lit", 2)
    end
    for row = 0, 2 do
        Rect(10, 38 + row * 14, 18, 3, o.text and "litfill" or "line", 4)
        for slot = 0, 2 do
            Rect(38 + slot * 31, 34 + row * 14, 27, 10, "raised", 4)
        end
    end
    -- the next step: a box with an accent bar, what to run and what it gives
    if o.next then
        Rect(6, 80, POPUP_W - 12, 22, "lit", 2)
    end
    Rect(10, 84, POPUP_W - 20, 14, "raised", 3)
    Rect(10, 84, 1.5, 14, o.accent and "litfill" or "line", 4)
    Rect(16, 87, 62, 3, o.text and "litfill" or "line", 4)
    Rect(16, 93, 92, 2, "line", 4)
    for line = 0, 3 do
        Rect(10, 104 + line * 9, 54, 3, o.text and "litfill" or "line", 3)
        Rect(POPUP_W - 38, 104 + line * 9, 28, 3, "line", 3)
    end
end

-- The minimap: its zone name, the map, Blizzard's addon menu and zoom buttons, and our button on
-- the edge at `angle` (degrees, the button's own). Returns the button's center.
local MINIMAP_R = 62

local function Minimap(o, cx, cy)
    cx, cy = cx or 210, cy or 92
    local zone = type(GetMinimapZoneText) == "function" and GetMinimapZoneText() or nil
    Label(cx, cy - MINIMAP_R - 8, Utils.IsUsableString(zone) and zone or "", "CENTER", nil,
        math.min(150, 2 * (CANVAS_W - 6 - cx)))
    Round(cx, cy, MINIMAP_R, "sk", 0)
    Round(cx, cy, MINIMAP_R - 10, "raised", 2)
    Round(cx + 47, cy - 47, 7, o.compartment and "lit" or "sk", 3)
    Round(cx + 52, cy + 38, 5, "sk", 3)
    Round(cx + 40, cy + 50, 5, "sk", 3)
    local angle = math.rad(o.angle or 220)
    local bx, by = cx + math.cos(angle) * (MINIMAP_R + 4), cy - math.sin(angle) * (MINIMAP_R + 4)
    if o.button ~= false then
        local alpha = o.faint and 0.35 or 1
        if o.faint then
            Round(bx, by, 12, hl, 4, 0.45)
            Round(bx, by, 11, CANVAS_BG, 5)
        end
        Round(bx, by, 9, o.lit and "lit" or "sk", 6, alpha)
        Round(bx, by, 4, o.lit and "litfill" or "line", 7, alpha)
        if o.lock then
            Rect(bx + 9, by - 13, 10, 8, "litfill", 7)
            Rect(bx + 11, by - 17, 1.5, 5, "litfill", 7)
            Rect(bx + 15.5, by - 17, 1.5, 5, "litfill", 7)
            Rect(bx + 11, by - 18, 6, 1.5, "litfill", 7)
        end
    end
    return bx, by, cx, cy
end

-- The chat frame: its tabs, a few dim lines, and one line lit with the reminder's own text.
local function Chat(lit)
    local general = type(GENERAL) == "string" and GENERAL or "General"
    local combatLog = type(COMBAT_LOG) == "string" and COMBAT_LOG or "Combat Log"
    Rect(10, 26, 62, 14, "sk", 0)
    Label(41, 33, general, "CENTER", nil, 56)
    Rect(74, 26, 76, 14, "raised", 0)
    Label(112, 33, combatLog, "CENTER", SK_LINE, 70)
    Rect(10, 40, 280, 110, "sk", 0)
    for line = 0, 4 do
        Rect(18, 52 + line * 12, 170 + (line * 37 % 60), 3, "line", 2)
    end
    if lit then
        Rect(14, 112, 272, 34, "lit", 3)
        Label(20, 118, "Better Great Vault: " .. L["Rewards are waiting in your Great Vault."], "TOPLEFT", hl, 260, true)
    end
    Rect(10, 156, 280, 12, "raised", 0)
end

-- Another addon's bag of minimap buttons.
local function ButtonBag()
    Label(2, 6, L["Button bag"], "LEFT", nil, 96)
    Rect(0, 14, 96, 28, "sk", 0)
    for index = 0, 3 do
        Round(14 + index * 22, 28, 7, "raised", 2)
    end
end

-- Blizzard's addon menu (the addon compartment's), with this addon's entry lit.
local function AddonMenu()
    local addons = type(ADDONS) == "string" and ADDONS or "AddOns"
    Rect(0, 0, 152, 64, "sk", 0)
    Label(6, 8, addons, "LEFT", nil, 140)
    Rect(8, 18, 70, 3, "line", 2)
    Rect(4, 26, 144, 15, "lit", 2)
    Label(10, 33, "Better Great Vault", "LEFT", hl, 134)
    Rect(8, 49, 60, 3, "line", 2)
end

-- The three windows an appearance option touches: the vault, the popup and the loot table.
local function AllWindows(o)
    Window(6, 8, 0.54, Vault, { done = { ["11"] = true, ["12"] = true, ["21"] = true }, text = o.text,
        slots = o.accent and { ["11"] = true } or nil })
    Window(6, 102, 0.55, Popup, { text = o.text, accent = o.accent, week = o.accent })
    Window(166, 8, 1, LootTable, { text = o.text, accent = o.accent })
end

-- The sketches, by option -----------------------------------------------------------------------
-- where: the part of the UI it shows; caption: what changes there, {lit} in the lit color. Both
-- are read when the card shows, in the language chosen then.

local SKETCHES = {
    anim = {
        where = function() return L["Great Vault"] end,
        caption = function() return L["An unlocked slot {opens onto its loot reel} when you point at it. Off: Blizzard's plain slots."] end,
        playing = true,
        draw = function()
            Vault({ slots = { ["11"] = true }, done = { ["11"] = true, ["12"] = true, ["21"] = true }, reel = true })
        end,
    },
    style = {
        where = function() return L["Great Vault"] end,
        caption = function() return L["How the slot's {gates open} before the reel shows. Pointing at a style in the menu plays it."] end,
        playing = true,
        draw = function()
            Vault({ slots = { ["11"] = true }, done = { ["12"] = true, ["21"] = true }, reel = true })
        end,
    },
    sad = {
        where = function() return L["Great Vault"] end,
        caption = function() return L["While you point at {%s}, your {completed slots} frown."] end,
        draw = function()
            Vault({ slots = { ["11"] = true, ["12"] = true, ["21"] = true },
                done = { ["11"] = true, ["12"] = true, ["21"] = true }, faces = true, collect = true })
            Cursor(150, 163)
        end,
    },
    bis = {
        where = function() return L["Great Vault and loot table"] end,
        caption = function() return L["{Item colors} in the reels and the loot table's {Tier column}."] end,
        draw = function()
            Window(6, 8, 0.54, Vault, { done = { ["12"] = true }, reel = true, tiers = true })
            Window(166, 8, 1, LootTable, { tiers = true })
        end,
    },
    click = {
        where = function() return L["Great Vault and loot table"] end,
        caption = function() return L["{Left-clicking a slot} opens {its loot table}. Off: clicks only select, as in Blizzard's vault."] end,
        draw = function()
            Window(6, 18, 0.5, Vault, { slots = { ["11"] = true }, done = { ["11"] = true } })
            Cursor(70, 40)
            Arrow(148, 70, 162, 70, hl)
            Window(170, 10, 1, LootTable, { lit = true, w = 124, h = 160 })
        end,
    },
    spec = {
        where = function() return L["Great Vault and loot table"] end,
        caption = function() return L["The {loot spec button} at the vault's top left and in the loot table's title bar."] end,
        draw = function()
            Window(6, 8, 0.54, Vault, { spec = true })
            Window(166, 8, 1, LootTable, { spec = true })
        end,
    },
    remind = {
        where = function() return L["Chat"] end,
        caption = function() return L["At login, {one chat line} when rewards wait in the vault."] end,
        draw = function()
            Chat(true)
        end,
    },
    compartment = {
        where = function() return L["Minimap"] end,
        caption = function() return L["An entry in {Blizzard's addon menu} on the minimap."] end,
        draw = function()
            -- the menu opens under its button, over the map
            Minimap({ compartment = true, button = false }, 216, 102)
            Window(108, 64, 1, AddonMenu)
        end,
    },
    button = {
        where = function() return L["Minimap"] end,
        caption = function() return L["The {button on the minimap's edge}."] end,
        draw = function()
            Minimap({ lit = true })
        end,
    },
    reset = {
        where = function() return L["Minimap"] end,
        caption = function() return L["Moves the button back to {its first spot}, bottom left."] end,
        draw = function()
            local bx, by, cx, cy = Minimap({ lit = true })
            local gx, gy = cx + math.cos(math.rad(70)) * 66, cy - math.sin(math.rad(70)) * 66
            Round(gx, gy, 9, hl, 4, 0.35)
            Round(gx, gy, 8, CANVAS_BG, 5)
            Dots(gx - 10, gy + 6, cx - 60, cy - 50, bx - 4, by - 12, hl)
        end,
    },
    popup = {
        where = function() return L["Minimap"] end,
        caption = function() return L["Pointing at the button opens {this popup}."] end,
        draw = function()
            local bx, by = Minimap({}, 232, 92)
            Window(30, 26, 1, Popup, { lit = true })
            Cursor(bx, by)
        end,
    },
    week = {
        where = function() return L["Minimap popup"] end,
        caption = function() return L["{This week's slots} in the popup: each slot's item level, or its progress."] end,
        draw = function()
            Minimap({}, 232, 92)
            Window(30, 26, 1, Popup, { week = true })
        end,
    },
    next = {
        where = function() return L["Minimap popup"] end,
        caption = function() return L["{The next step} in the popup: what to run to unlock a slot or raise a reward."] end,
        draw = function()
            Minimap({}, 232, 92)
            Window(30, 26, 1, Popup, { next = true })
        end,
    },
    lock = {
        where = function() return L["Minimap"] end,
        caption = function() return L["The button {can't be dragged} while locked."] end,
        draw = function()
            Minimap({ lit = true, lock = true })
        end,
    },
    keep = {
        where = function() return L["Minimap"] end,
        caption = function() return L["The button {stays on the minimap} instead of a button-gathering addon's bag."] end,
        draw = function()
            local bx, by = Minimap({ lit = true })
            Window(14, 104, 1, ButtonBag)
            Bar(114, 132, bx - 14, by + 6, 1, hl, 5)
            Bar(118, 116, 128, 126, 1.5, hl, 6)
            Bar(128, 116, 118, 126, 1.5, hl, 6)
        end,
    },
    fade = {
        where = function() return L["Minimap"] end,
        caption = function() return L["The button is {faint} until you point at it, and full while rewards wait."] end,
        draw = function()
            Minimap({ lit = true, faint = true })
        end,
    },
    text = {
        where = function() return L["All windows"] end,
        caption = function() return L["Every piece of {the addon's text}: slot captions, the popup, the loot table."] end,
        draw = function()
            AllWindows({ text = true })
        end,
    },
    speccolor = {
        where = function() return L["All windows"] end,
        caption = function() return L["Highlights in {your spec's color}: slot borders, the popup, the loot table's header."] end,
        color = function()
            return Utils.SpecAccent()
        end,
        draw = function()
            AllWindows({ accent = true })
        end,
    },
    accent = {
        where = function() return L["All windows"] end,
        caption = function() return L["The same places, in {the color you pick}, while your spec's color is off."] end,
        color = function()
            local saved = BetterGreatVaultDB and BetterGreatVaultDB.accentColor
            if type(saved) == "table" then
                local r, g, b = saved.r or saved[1], saved.g or saved[2], saved.b or saved[3]
                if type(r) == "number" and type(g) == "number" and type(b) == "number" then
                    return { r, g, b }
                end
            end
            return { 0.85, 0.65, 0.2 }
        end,
        draw = function()
            AllWindows({ accent = true })
        end,
    },
}
Preview.SKETCHES = SKETCHES

-- The card --------------------------------------------------------------------------------------

local function Build()
    if card then
        return card
    end
    card = CreateFrame("Frame", "BetterGreatVaultSettingsPreview", UIParent)
    card:SetFrameStrata("TOOLTIP")
    card:EnableMouse(false)
    if card.SetClampedToScreen then
        card:SetClampedToScreen(true)
    end
    card:SetWidth(CANVAS_W + PAD * 2)
    local back = Utils.Pixel(card, "BACKGROUND", CARD_BG[1], CARD_BG[2], CARD_BG[3], 0.98)
    back:SetAllPoints()
    Utils.Border(card, CARD_EDGE[1], CARD_EDGE[2], CARD_EDGE[3], 1)
    card.bar = Utils.Pixel(card, "ARTWORK", 0.85, 0.65, 0.2, 1)
    card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
    card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
    card.bar:SetHeight(BAR_H)

    card.title = Utils.FontString(card, "OVERLAY", "Highlight")
    card.title:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -(BAR_H + 10))
    card.title:SetJustifyH("LEFT")
    card.title:SetWordWrap(false)
    card.where = Utils.FontString(card, "OVERLAY", "Disable")
    card.where:SetPoint("TOPRIGHT", card, "TOPRIGHT", -PAD, -(BAR_H + 11))
    card.where:SetJustifyH("RIGHT")
    card.where:SetWordWrap(false)
    card.title:SetPoint("RIGHT", card.where, "LEFT", -10, 0)

    canvas = CreateFrame("Frame", nil, card)
    canvas:SetSize(CANVAS_W, CANVAS_H)
    local ground = Utils.Pixel(canvas, "BACKGROUND", CANVAS_BG[1], CANVAS_BG[2], CANVAS_BG[3], 1)
    ground:SetAllPoints()
    Utils.Border(canvas, 0.122, 0.125, 0.137, 1)
    card.canvas = canvas

    card.caption = Utils.FontString(card, "OVERLAY", "Disable")
    card.caption:SetJustifyH("LEFT")
    card.caption:SetJustifyV("TOP")
    card.caption:SetWordWrap(true)
    card.caption:SetWidth(CANVAS_W)
    card.caption:SetTextColor(0.62, 0.61, 0.58)
    card:Hide()
    return card
end

local function Hex(color)
    return string.format("%02x%02x%02x", math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5),
        math.floor(color[3] * 255 + 0.5))
end

-- The caption, its {lit} parts in the lit color. A caption with %s gets the game's name for
-- Collect (put in as plain text: a stray % in a translation can't break it).
local function Caption(text)
    local start, finish = text:find("%s", 1, true)
    if start then
        local collect = type(WEEKLY_REWARDS_GET_CONCESSION) == "string" and WEEKLY_REWARDS_GET_CONCESSION or "Collect"
        text = text:sub(1, start - 1) .. collect .. text:sub(finish + 1)
    end
    local hex = Hex(hl)
    return (text:gsub("{(.-)}", function(lit)
        return "|cff" .. hex .. lit .. "|r"
    end))
end

-- Lays the card out around its text: title, canvas, caption.
local function Fit()
    local titleH = math.max(Metric(card.title:GetStringHeight()) or 14, 12)
    local top = BAR_H + 10 + titleH + 8
    canvas:ClearAllPoints()
    canvas:SetPoint("TOPLEFT", card, "TOPLEFT", PAD, -top)
    card.caption:ClearAllPoints()
    card.caption:SetPoint("TOPLEFT", canvas, "BOTTOMLEFT", 0, -8)
    local captionH = math.max(Metric(card.caption:GetStringHeight()) or 28, 12)
    card:SetHeight(top + CANVAS_H + 8 + captionH + PAD)
end

-- Under the option, flush with the page's right edge; above it when there's no room below.
local function Place(owner)
    card:ClearAllPoints()
    local anchor = page or owner
    local anchorScale = Metric(anchor:GetEffectiveScale()) or 1
    local ownerScale = Metric(owner:GetEffectiveScale()) or 1
    local cardScale = Metric(card:GetEffectiveScale()) or 1
    local top = Metric(anchor:GetTop())
    local ownerTop, ownerBottom = Metric(owner:GetTop()), Metric(owner:GetBottom())
    if not (top and ownerTop and ownerBottom and anchorScale > 0 and cardScale > 0) then
        card:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -6)
        return
    end
    local scale = anchorScale / cardScale
    local height = Metric(card:GetHeight()) or 0
    local below = ownerBottom * ownerScale - height * cardScale
    if below > 8 then
        card:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -24 * scale, (ownerBottom - top - 6) * scale)
    else
        card:SetPoint("BOTTOMRIGHT", anchor, "TOPRIGHT", -24 * scale, (ownerTop - top + 6) * scale)
    end
end

-- The opening itself, playing in the sketch's place (Case.ShowPreview), for the options about it.
local PLAY_SCALE = 0.72

local function PlayOpening()
    local Case = BGV.Case
    if not (Case and type(Case.ShowPreview) == "function") or Utils.AnimationsOff() then
        return false
    end
    return Case.ShowPreview(canvas, Case.Choice(), function(panel)
        panel:SetScale(PLAY_SCALE)
        panel:SetFrameLevel(card:GetFrameLevel() + 20)
        panel:ClearAllPoints()
        panel:SetPoint("TOPRIGHT", canvas, "TOPRIGHT", -6 / PLAY_SCALE, -6 / PLAY_SCALE)
    end) == true
end

local function StopOpening()
    if playing and BGV.Case and type(BGV.Case.HidePreview) == "function" then
        BGV.Case.HidePreview()
    end
    playing = false
end

local function Show(owner, key, title)
    local sketch = SKETCHES[key]
    if not sketch then
        return
    end
    Build()
    StopOpening()
    SetLitColor(sketch.color and sketch.color() or Utils.AccentColor())
    local accent = Utils.AccentColor()
    card.bar:SetVertexColor(accent[1], accent[2], accent[3], 1)
    card.title:SetText(type(title) == "function" and title() or title or "")
    card.where:SetText(sketch.where())
    card.caption:SetText(Caption(sketch.caption()))
    Clear()
    playing = sketch.playing and PlayOpening() or false
    if playing then
        -- the vault, small, beside the opening: which slot it is
        Window(8, 58, 0.36, Vault, { slots = { ["11"] = true }, done = { ["12"] = true, ["21"] = true } })
    else
        sketch.draw()
    end
    -- shown unseen first: text is measured right only on a shown frame
    card:SetAlpha(0)
    card:Show()
    Fit()
    Place(owner)
    card:SetAlpha(1)
    shownFor = shownFor or {}
    shownFor.owner, shownFor.key, shownFor.title = owner, key, title
end

local function Hide()
    token = token + 1
    StopOpening()
    if shownFor then
        shownFor.owner = nil
    end
    if card then
        card:Hide()
    end
end
Preview.Hide = Utils.Protect("settings preview", Hide)

-- The option was clicked (its new state already set): the card it shows is drawn again, so it
-- shows the change, e.g. the new accent color.
local Redraw = Utils.Protect("settings preview", function(owner)
    if shownFor and shownFor.owner == owner and card and card:IsShown() and not InCombat() then
        Show(owner, shownFor.key, shownFor.title)
    end
end)

-- Paints the sketch `key` onto `frame`, a CANVAS_W x CANVAS_H surface (scale it with SetScale),
-- still and without labels: the news popup's previews. `color`: the lit color (the accent).
Preview.Draw = Utils.Protect("settings preview", function(frame, key, color)
    local sketch = SKETCHES[key]
    if not (frame and sketch) then
        return
    end
    local ownCanvas, ownSheets = canvas, sheets
    frame.bgvSheets = frame.bgvSheets or {}
    canvas, sheets = frame, frame.bgvSheets
    bare = true
    local ok, err = pcall(function()
        SetLitColor(color or Utils.AccentColor())
        Clear()
        sketch.draw()
    end)
    bare = false
    canvas, sheets, sheet = ownCanvas, ownSheets, nil
    ox, oy, sc, nextSheet = 0, 0, 1, 2
    if not ok then
        error(err, 0)
    end
end)
Preview.CANVAS_W, Preview.CANVAS_H = CANVAS_W, CANVAS_H

-- The settings page, which the card lines up with.
function Preview.SetPage(frame)
    page = frame
end

-- How many pieces the pools hold (tests: a second round of hovers makes none).
function Preview.PoolSizes()
    local textureCount, discCount, labelCount = 0, 0, 0
    for _, each in ipairs(sheets) do
        textureCount, discCount, labelCount = textureCount + #each.textures, discCount + #each.discs, labelCount + #each.labels
    end
    return textureCount, discCount, labelCount
end

-- Shows the sketch `key` (SKETCHES) while the pointer rests on `frame`, never in combat.
-- `title`: the option's name, or a function giving it. A click keeps the card and draws it again
-- with the option's new state; `hideOnClick` closes it instead, for a control that opens
-- something over it (a menu, the color picker). Everything runs caught (Utils.Protect): a mistake
-- here never reaches the game's error frame.
function Preview.Attach(frame, key, title, hideOnClick)
    if not (frame and SKETCHES[key]) then
        return
    end
    local function Rested(owner, mine)
        if token == mine and owner:IsVisible() and not InCombat() then
            Show(owner, key, title)
        end
    end
    frame:HookScript("OnEnter", Utils.Protect("settings preview", function(self)
        token = token + 1
        if InCombat() or not (C_Timer and type(C_Timer.After) == "function") then
            return
        end
        local mine = token
        C_Timer.After(DELAY, Utils.Protect("settings preview", function()
            Rested(self, mine)
        end))
    end))
    frame:HookScript("OnLeave", Preview.Hide)
    frame:HookScript("OnHide", Preview.Hide)
    if hideOnClick then
        frame:HookScript("OnMouseDown", Preview.Hide)
    elseif frame:GetObjectType() == "Slider" then
        -- a slider's value is set while it's dragged: drawn again once it's let go
        frame:HookScript("OnMouseUp", Redraw)
    else
        frame:HookScript("OnClick", Redraw)
    end
end
