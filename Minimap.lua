local _, BGV = ...

BGV.Minimap = {}

local Utils = BGV.Utils
local MEDIA = "Interface\\AddOns\\BetterGreatVault\\Media\\"
local RADIUS = 80

local function ShowMinimap()
    return not BetterGreatVaultDB or BetterGreatVaultDB.showMinimap ~= false
end

local function LoadVaultUI()
    BGV.Utils.LoadAddon("Blizzard_WeeklyRewards")
end

local function VaultShown()
    return WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown()
end

function BGV.Minimap.ToggleVault()
    LoadVaultUI()
    if VaultShown() then
        WeeklyRewardsFrame:Hide()
        return
    end
    if type(WeeklyRewards_Show) == "function" then
        WeeklyRewards_Show()
    elseif WeeklyRewardsFrame and type(WeeklyRewardsFrame.Show) == "function" then
        WeeklyRewardsFrame:Show()
    end
end

function BGV.Minimap.ToggleSettings()
    if BGV.Settings and type(BGV.Settings.Toggle) == "function" then
        BGV.Settings.Toggle()
    end
end

local button = CreateFrame("Button", "BetterGreatVaultMinimapButton", Minimap)
button:SetSize(32, 32)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:RegisterForClicks("AnyUp")
button:RegisterForDrag("LeftButton")
button:Hide()

-- The vault door emblem in layers: the rim and door, the handle (turns a quarter on hover, like
-- unlocking), the gem, the gem's pulse (rewards waiting to be claimed), and a glow behind it in
-- the accent color (hover). The rim is the button's icon; every other layer is anchored to it, so
-- they stay together when a minimap button skin (e.g. EllesmereUI's) re-anchors or crops the icon.
local function Layer(file, drawLayer, sublevel)
    local texture = button:CreateTexture(nil, drawLayer, nil, sublevel)
    texture:SetTexture(MEDIA .. file)
    return texture
end

local base = Layer("MinimapBase", "ARTWORK", 0)
base:SetAllPoints(button)
button.icon = base

local function Around(texture, inset)
    texture:SetPoint("TOPLEFT", base, "TOPLEFT", -inset, inset)
    texture:SetPoint("BOTTOMRIGHT", base, "BOTTOMRIGHT", inset, -inset)
    return texture
end

local wheel = Around(Layer("MinimapWheel", "ARTWORK", 1), 0)
local gem = Around(Layer("MinimapGem", "OVERLAY", 0), 0)
local gemPulse = Around(Layer("MinimapGem", "OVERLAY", 1), 3)
gemPulse:SetBlendMode("ADD")
gemPulse:SetAlpha(0)
local glow = Around(Layer("MinimapGlow", "BACKGROUND", 0), 13)
glow:SetBlendMode("ADD")
glow:SetAlpha(0)

-- Pressed: the emblem darkens a little. (Colors only: moving the layers would undo a skin's layout.)
local function Press(down)
    local shade = down and 0.72 or 1
    for _, texture in ipairs({ base, wheel, gem }) do
        texture:SetVertexColor(shade, shade, shade)
    end
end

button:SetScript("OnMouseDown", function()
    Press(true)
end)
button:SetScript("OnMouseUp", function()
    Press(false)
end)

-- Hover: the handle eases a quarter turn and the glow fades in, and back on leave. Driven by an
-- OnUpdate that only runs while something is still moving.
local motion = { angle = 0, target = 0, glow = 0, glowTarget = 0 }
local animator = CreateFrame("Frame", nil, button)

local function Step(_, elapsed)
    motion.angle = motion.angle + (motion.target - motion.angle) * math.min(1, elapsed * 9)
    motion.glow = motion.glow + (motion.glowTarget - motion.glow) * math.min(1, elapsed * 12)
    if math.abs(motion.target - motion.angle) < 0.2 and math.abs(motion.glowTarget - motion.glow) < 0.01 then
        motion.angle, motion.glow = motion.target, motion.glowTarget
        animator:SetScript("OnUpdate", nil)
    end
    wheel:SetRotation(math.rad(motion.angle))
    glow:SetAlpha(motion.glow)
end

local function AnimateTo(angle, glowAlpha)
    motion.target, motion.glowTarget = angle, glowAlpha
    animator:SetScript("OnUpdate", Step)
end

-- Rewards waiting in the vault: the gem pulses until they're claimed.
local pulse = gemPulse:CreateAnimationGroup()
pulse:SetLooping("BOUNCE")
local fade = pulse:CreateAnimation("Alpha")
fade:SetFromAlpha(0)
fade:SetToAlpha(0.9)
fade:SetDuration(1)
fade:SetSmoothing("IN_OUT")

local function RewardsWaiting()
    return C_WeeklyRewards and type(C_WeeklyRewards.HasAvailableRewards) == "function"
        and C_WeeklyRewards.HasAvailableRewards() == true
end

function BGV.Minimap.RefreshAttention()
    if RewardsWaiting() then
        if not pulse:IsPlaying() then
            pulse:Play()
        end
    else
        pulse:Stop()
        gemPulse:SetAlpha(0)
    end
end

-- The button is ours to place while it sits on the minimap. A minimap button addon can move it
-- into a frame of its own (EllesmereUI's button group), which places it from then on.
local function OnMinimap()
    return button:GetParent() == Minimap
end

local function Place()
    if not OnMinimap() then
        return
    end
    local angle = BetterGreatVaultDB and BetterGreatVaultDB.minimapAngle or 220
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

local placed = false

-- Shows or hides the button as the settings say. It's placed the first time it's shown, and
-- again with `reposition` (settings reset); turning it off and on leaves it where it is, which a
-- minimap button addon may have chosen.
function BGV.Minimap.Apply(reposition)
    if ShowMinimap() then
        if not placed or reposition then
            Place()
            placed = true
        end
        -- Showing it must not leave it invisible: in its own frame, a minimap button addon's Show
        -- hook can zero the alpha until that addon lays the frame out again (EllesmereUI's does).
        local alpha = button:GetAlpha()
        button:Show()
        if not OnMinimap() and button:GetAlpha() < alpha then
            button:SetAlpha(alpha)
        end
        BGV.Minimap.RefreshAttention()
    else
        button:Hide()
    end
end

-- The hover popup, in the loot table's flat style: this week's vault slots (the reward's item
-- level once a slot is unlocked, progress until then) and what each click does, with the accent
-- color. Built on the first hover and refreshed on each one.
local POPUP_W = 300
local PAD = 12
local HEADER_H = 46
local LABEL_W = 78
local CHIP_W = 62
local CHIP_H = 20
local CHIP_GAP = 6
local CALLOUT_H = 40
local ROW_TYPES = { "Raid", "Activities", "World" }
local ACTIONS = {
    { key = "Left-click" },
    { key = "Middle-click", text = "Possible loot from your slots" },
    { key = "Shift + middle-click", text = "Loot database, any class" },
    { key = "Right-click", text = "Settings" },
    { key = "Drag", text = "Move this button" },
}

local popup
local LayoutPopup

local function Text(font, r, g, b)
    local text = popup:CreateFontString(nil, "OVERLAY", font)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    text:SetTextColor(r, g, b)
    return text
end

local function BuildPopup()
    if popup then
        return
    end
    local Pixel = Utils.Pixel
    popup = CreateFrame("Frame", "BetterGreatVaultMinimapPopup", UIParent)
    popup:SetFrameStrata("TOOLTIP")
    popup:SetClampedToScreen(true)
    popup:SetWidth(POPUP_W)
    popup:Hide()
    for step, alpha in ipairs({ 0.22, 0.14, 0.07 }) do
        local shadow = Pixel(popup, "BACKGROUND", 0, 0, 0, alpha)
        shadow:SetDrawLayer("BACKGROUND", -8)
        shadow:SetPoint("TOPLEFT", -2 * step, 2 * step)
        shadow:SetPoint("BOTTOMRIGHT", 2 * step, -2 * step)
    end
    local body = Pixel(popup, "BACKGROUND", 0.055, 0.055, 0.065, 0.97)
    body:SetDrawLayer("BACKGROUND", -7)
    body:SetAllPoints()
    Utils.Border(popup, 0.24, 0.24, 0.27, 1)

    -- Title band: the emblem, the addon's name and the time left to the weekly reset, over a
    -- rule in the accent color.
    local band = Pixel(popup, "BACKGROUND", 0.085, 0.085, 0.097, 1)
    band:SetPoint("TOPLEFT", 1, -1)
    band:SetPoint("TOPRIGHT", -1, -1)
    band:SetHeight(HEADER_H - 1)
    popup.rule = Pixel(popup, "ARTWORK", 1, 1, 1, 1)
    popup.rule:SetHeight(1)
    popup.rule:SetPoint("TOPLEFT", band, "BOTTOMLEFT", 0, 0)
    popup.rule:SetPoint("TOPRIGHT", band, "BOTTOMRIGHT", 0, 0)
    local emblem = popup:CreateTexture(nil, "ARTWORK")
    emblem:SetTexture("Interface\\AddOns\\BetterGreatVault\\Icon")
    emblem:SetSize(30, 30)
    emblem:SetPoint("TOPLEFT", PAD - 2, -8)
    popup.title = Text("GameFontNormal", 0.85, 0.65, 0.2)
    popup.title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 8, -2)
    popup.title:SetText("Better Great Vault")
    popup.subtitle = Text("GameFontHighlightSmall", 0.55, 0.55, 0.58)
    popup.subtitle:SetPoint("TOPLEFT", popup.title, "BOTTOMLEFT", 0, -3)

    -- Rewards waiting to be claimed: a callout with an accent bar.
    popup.callout = Pixel(popup, "ARTWORK", 1, 1, 1, 1)
    popup.callout:SetHeight(CALLOUT_H)
    popup.calloutBar = Pixel(popup, "ARTWORK", 1, 1, 1, 1)
    popup.calloutBar:SetDrawLayer("ARTWORK", 1)
    popup.calloutBar:SetWidth(2)
    popup.calloutBar:SetPoint("TOPLEFT", popup.callout, "TOPLEFT", 0, 0)
    popup.calloutBar:SetPoint("BOTTOMLEFT", popup.callout, "BOTTOMLEFT", 0, 0)
    popup.calloutTitle = Text("GameFontNormal", 0.96, 0.96, 0.96)
    popup.calloutTitle:SetPoint("TOPLEFT", popup.callout, "TOPLEFT", 12, -7)
    popup.calloutTitle:SetText("Rewards are waiting")
    popup.calloutText = Text("GameFontHighlightSmall", 0.7, 0.7, 0.74)
    popup.calloutText:SetPoint("TOPLEFT", popup.calloutTitle, "BOTTOMLEFT", 0, -3)
    popup.calloutText:SetText("Choose one in the Great Vault")

    -- This week's slots: a heading, then a row of chips for each row of the vault.
    popup.heading = Text("GameFontNormalSmall", 0.66, 0.66, 0.7)
    popup.heading:SetText("THIS WEEK")
    popup.count = Text("GameFontHighlightSmall", 0.55, 0.55, 0.58)
    popup.count:SetJustifyH("RIGHT")
    popup.note = Text("GameFontHighlightSmall", 0.55, 0.55, 0.58)
    popup.note:SetText("Great Vault progress isn't available yet")
    popup.rows = {}
    for index = 1, #ROW_TYPES do
        local row = { chips = {} }
        row.label = Text("GameFontNormalSmall", 0.66, 0.66, 0.7)
        row.label:SetWidth(LABEL_W - 6)
        for chipIndex = 1, 3 do
            local chip = {}
            chip.fill = Pixel(popup, "ARTWORK", 1, 1, 1, 1)
            chip.fill:SetSize(CHIP_W, CHIP_H)
            chip.bar = Pixel(popup, "ARTWORK", 1, 1, 1, 1)
            chip.bar:SetDrawLayer("ARTWORK", 1)
            chip.bar:SetHeight(2)
            chip.bar:SetPoint("BOTTOMLEFT", chip.fill, "BOTTOMLEFT", 0, 0)
            chip.text = Text("GameFontHighlightSmall", 0.96, 0.96, 0.96)
            chip.text:SetWidth(CHIP_W - 4)
            chip.text:SetJustifyH("CENTER")
            chip.text:SetPoint("CENTER", chip.fill, "CENTER", 0, 1)
            row.chips[chipIndex] = chip
        end
        popup.rows[index] = row
    end

    -- What each click does: the action, and its mouse button in the accent color.
    popup.divider = Pixel(popup, "ARTWORK", 1, 1, 1, 0.08)
    popup.divider:SetHeight(1)
    popup.actions = {}
    for index, action in ipairs(ACTIONS) do
        local line = {}
        line.text = Text("GameFontHighlightSmall", 0.9, 0.9, 0.92)
        line.text:SetText(action.text or "")
        line.key = Text("GameFontNormalSmall", 1, 1, 1)
        line.key:SetJustifyH("RIGHT")
        line.key:SetText(action.key)
        popup.actions[index] = line
    end
end

local function ResetText()
    local seconds = C_DateAndTime and type(C_DateAndTime.GetSecondsUntilWeeklyReset) == "function"
        and C_DateAndTime.GetSecondsUntilWeeklyReset()
    if not Utils.IsUsableNumber(seconds) or seconds <= 0 then
        return "Your weekly Great Vault"
    end
    local days = math.floor(seconds / 86400)
    local hours = math.floor(seconds % 86400 / 3600)
    local minutes = math.floor(seconds % 3600 / 60)
    if days > 0 then
        return string.format("Weekly reset in %dd %dh", days, hours)
    end
    if hours > 0 then
        return string.format("Weekly reset in %dh %dm", hours, minutes)
    end
    return string.format("Weekly reset in %dm", math.max(1, minutes))
end

-- The vault shows this week's progress (not last week's rewards to claim); same test as the vault's.
local function ProgressWeek()
    return not (BGV.Rewards and type(BGV.Rewards.ShowingWeeklyProgress) == "function")
        or BGV.Rewards.ShowingWeeklyProgress()
end

-- The vault's slots for each row, from the snapshot the vault itself shows (cached until the
-- vault's data changes).
local function WeekRows()
    local vault = BGV.GreatVault
    local ok, snapshot = false, nil
    if vault and type(vault.GetSnapshot) == "function" then
        ok, snapshot = pcall(vault.GetSnapshot)
    end
    local rows = {}
    if not ok or type(snapshot) ~= "table" then
        return rows
    end
    for _, name in ipairs(ROW_TYPES) do
        local rowType = Utils.ThresholdType(name)
        local slots = {}
        for _, slot in ipairs(snapshot) do
            if type(slot) == "table" and Utils.SameType(slot.type, rowType) then
                slots[#slots + 1] = slot
            end
        end
        table.sort(slots, function(left, right)
            return (left.index or 0) < (right.index or 0)
        end)
        if #slots > 0 then
            rows[#rows + 1] = slots
        end
    end
    return rows
end

-- A slot unlocked before its reward item loaded: look the reward up again, as the vault does,
-- and show its item level once the item arrives. Kept here: the vault's snapshot is left as is.
local lookups = setmetatable({}, { __mode = "k" })

local function SlotItemLevel(slot)
    if Utils.IsUsableNumber(slot.itemLevel) then
        return slot.itemLevel
    end
    local lookup = lookups[slot]
    if lookup then
        return lookup.itemLevel
    end
    if type(slot.source) ~= "table" or not (BGV.Rewards and type(BGV.Rewards.ResolveReward) == "function") then
        return nil
    end
    lookup = {}
    lookups[slot] = lookup
    local info = BGV.Rewards.ResolveReward(slot.source, function(ready)
        if type(ready) == "table" and Utils.IsUsableNumber(ready.itemLevel) then
            lookup.itemLevel = ready.itemLevel
            if popup and popup:IsShown() then
                LayoutPopup()
            end
        end
    end)
    if type(info) == "table" and Utils.IsUsableNumber(info.itemLevel) then
        lookup.itemLevel = info.itemLevel
    end
    return lookup.itemLevel
end

-- Unlocked: filled with the accent and showing the reward's item level (the vault's number; the
-- difficulty or key level while the item loads). Locked: the progress, with a bar toward it.
local function PaintChip(chip, slot, accent)
    local r, g, b = accent[1], accent[2], accent[3]
    if slot.unlocked then
        local itemLevel = SlotItemLevel(slot)
        chip.fill:SetVertexColor(r, g, b, 0.24)
        chip.bar:SetVertexColor(r, g, b, 1)
        chip.bar:SetWidth(CHIP_W)
        chip.bar:Show()
        chip.text:SetTextColor(0.96, 0.96, 0.96)
        chip.text:SetText(itemLevel and tostring(itemLevel) or slot.qualifier or "Unlocked")
        return
    end
    local progress = Utils.IsUsableNumber(slot.progress) and slot.progress or 0
    local threshold = Utils.IsUsableNumber(slot.threshold) and slot.threshold or 0
    local share = threshold > 0 and math.max(0, math.min(1, progress / threshold)) or 0
    chip.fill:SetVertexColor(1, 1, 1, 0.05)
    chip.bar:SetVertexColor(r, g, b, 0.6)
    chip.bar:SetWidth(math.max(1, math.floor(CHIP_W * share + 0.5)))
    chip.bar:SetShown(share > 0)
    chip.text:SetTextColor(0.6, 0.6, 0.64)
    chip.text:SetText(string.format("%d/%d", progress, threshold))
end

local function PlaceAt(region, x, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -y)
end

local function LayoutWeek(y, accent)
    local rows = WeekRows()
    local unlocked, total = 0, 0
    for _, slots in ipairs(rows) do
        for _, slot in ipairs(slots) do
            total = total + 1
            unlocked = unlocked + (slot.unlocked and 1 or 0)
        end
    end
    PlaceAt(popup.heading, PAD, y)
    popup.count:ClearAllPoints()
    popup.count:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -y)
    popup.count:SetText(string.format("%d of %d unlocked", unlocked, total))
    popup.count:SetShown(total > 0)
    y = y + 18
    popup.note:SetShown(total == 0)
    if total == 0 then
        PlaceAt(popup.note, PAD, y)
        y = y + 16
    end
    for index, row in ipairs(popup.rows) do
        local slots = rows[index]
        row.label:SetShown(slots ~= nil)
        if slots then
            row.label:ClearAllPoints()
            row.label:SetPoint("LEFT", popup, "TOPLEFT", PAD, -(y + CHIP_H / 2))
            row.label:SetText(BGV.GreatVault.CategoryName(slots[1].type):upper())
        end
        for chipIndex, chip in ipairs(row.chips) do
            local slot = slots and slots[chipIndex]
            chip.fill:SetShown(slot ~= nil)
            chip.text:SetShown(slot ~= nil)
            if slot then
                PlaceAt(chip.fill, PAD + LABEL_W + (chipIndex - 1) * (CHIP_W + CHIP_GAP), y)
                PaintChip(chip, slot, accent)
            else
                chip.bar:Hide()
            end
        end
        if slots then
            y = y + CHIP_H + CHIP_GAP
        end
    end
    return y + 4
end

function LayoutPopup()
    local accent = Utils.AccentColor()
    local r, g, b = accent[1], accent[2], accent[3]
    popup.rule:SetVertexColor(r, g, b, 0.6)
    popup.subtitle:SetText(ResetText())
    local y = HEADER_H + 12

    local waiting = RewardsWaiting() == true
    popup.callout:SetShown(waiting)
    popup.calloutBar:SetShown(waiting)
    popup.calloutTitle:SetShown(waiting)
    popup.calloutText:SetShown(waiting)
    if waiting then
        PlaceAt(popup.callout, PAD, y)
        popup.callout:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -y)
        popup.callout:SetVertexColor(r, g, b, 0.12)
        popup.calloutBar:SetVertexColor(r, g, b, 1)
        y = y + CALLOUT_H + 12
    end

    -- Like the vault, the week's slots only while it shows the week's progress.
    local week = ProgressWeek() == true
    popup.heading:SetShown(week)
    if week then
        y = LayoutWeek(y, accent)
    else
        popup.count:Hide()
        popup.note:Hide()
        for _, row in ipairs(popup.rows) do
            row.label:Hide()
            for _, chip in ipairs(row.chips) do
                chip.fill:Hide()
                chip.bar:Hide()
                chip.text:Hide()
            end
        end
    end

    popup.divider:SetShown(waiting or week)
    if waiting or week then
        PlaceAt(popup.divider, PAD, y)
        popup.divider:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -y)
        y = y + 11
    else
        y = HEADER_H + 10
    end
    popup.actions[1].text:SetText(VaultShown() and "Close the Great Vault" or "Open the Great Vault")
    for _, line in ipairs(popup.actions) do
        PlaceAt(line.text, PAD, y)
        line.key:ClearAllPoints()
        line.key:SetPoint("TOPRIGHT", popup, "TOPRIGHT", -PAD, -y)
        line.key:SetTextColor(r, g, b)
        y = y + 17
    end
    popup:SetHeight(y + PAD - 5)
end

-- Beside the button, toward the middle of the screen.
local function AnchorPopup(owner)
    popup:ClearAllPoints()
    local x, y = owner:GetCenter()
    local scale = owner:GetEffectiveScale() / UIParent:GetEffectiveScale()
    local right = x and x * scale > UIParent:GetWidth() / 2
    local top = y and y * scale > UIParent:GetHeight() / 2
    local vertical = top and "TOP" or "BOTTOM"
    popup:SetPoint(vertical .. (right and "RIGHT" or "LEFT"), owner, vertical .. (right and "LEFT" or "RIGHT"), right and -8 or 8, 0)
end

local function ShowPopup(owner)
    BuildPopup()
    LayoutPopup()
    AnchorPopup(owner)
    popup:Show()
end

local function HidePopup()
    if popup then
        popup:Hide()
    end
end

button:SetScript("OnClick", function(self, mouseButton)
    if self.dragged then
        self.dragged = false
        return
    end
    if mouseButton == "RightButton" then
        BGV.Minimap.ToggleSettings()
    elseif mouseButton == "MiddleButton" then
        if not BGV.LootTable then
            return
        end
        if IsShiftKeyDown() and type(BGV.LootTable.ToggleDatabase) == "function" then
            BGV.LootTable.ToggleDatabase()
        elseif type(BGV.LootTable.Toggle) == "function" then
            BGV.LootTable.Toggle()
        end
    else
        BGV.Minimap.ToggleVault()
    end
    if popup and popup:IsShown() then
        LayoutPopup()
    end
end)

button:SetScript("OnDragStart", function(self)
    HidePopup()
    self.dragging = true
    self.dragged = true
    self:SetScript("OnUpdate", function(buttonFrame)
        if not buttonFrame.dragging or not Minimap then
            buttonFrame:SetScript("OnUpdate", nil)
            return
        end
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        if not mx or not scale or scale == 0 or not OnMinimap() then
            return
        end
        local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
        BetterGreatVaultDB.minimapAngle = angle
        Place()
    end)
end)

button:SetScript("OnDragStop", function(self)
    self.dragging = false
    self:SetScript("OnUpdate", nil)
end)

button:SetScript("OnEnter", function(self)
    local accent = Utils.AccentColor()
    glow:SetVertexColor(accent[1], accent[2], accent[3])
    AnimateTo(-90, 0.6)
    ShowPopup(self)
end)

button:SetScript("OnLeave", function()
    Press(false)
    AnimateTo(0, 0)
    HidePopup()
end)

button:SetScript("OnHide", HidePopup)

function BGV.Minimap.RegisterSettings()
    BGV.Minimap.Apply()
    if BGV.Settings and type(BGV.Settings.RegisterBridge) == "function" then
        BGV.Settings.RegisterBridge()
    end
end
