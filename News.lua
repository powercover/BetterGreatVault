local _, BGV = ...

-- What's new: the latest feature worth a word, only when asked for: clicking the version in the
-- settings' About, or /bgv news. It never opens by itself. Escape or "Got it" close it. Its
-- previews are the settings' own sketches (SettingsPreview.Draw), still and small.

BGV.News = {}

local News = BGV.News
local Utils = BGV.Utils
local L = BGV.L

local WIDTH = 480
local PAD = 26
local PREVIEWS = { "bis", "week", "remind" }
local SMALL, BIG = 0.4, 0.46 -- the previews' scale; the middle one stands out

local popup

local function InCombat()
    return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

local function Text(parent, key, r, g, b)
    local text = Utils.FontString(parent, "OVERLAY", key)
    text:SetJustifyH("CENTER")
    text:SetWordWrap(true)
    text:SetTextColor(r, g, b)
    return text
end

-- One preview: a card holding a sketch at `scale`, the middle one with an accent bar on top.
local function MakePreview(parent, scale, featured)
    local Preview = BGV.SettingsPreview
    local w, h = Preview.CANVAS_W * scale, Preview.CANVAS_H * scale
    local card = CreateFrame("Frame", nil, parent)
    card:SetSize(w + 10, h + 10)
    Utils.Pixel(card, "BACKGROUND", 0.067, 0.067, 0.071, 1):SetAllPoints()
    Utils.Border(card, 0.173, 0.176, 0.192, 1)
    if featured then
        card.bar = Utils.Pixel(card, "ARTWORK", 0.85, 0.65, 0.2, 1)
        card.bar:SetPoint("TOPLEFT", card, "TOPLEFT", 0, 0)
        card.bar:SetPoint("TOPRIGHT", card, "TOPRIGHT", 0, 0)
        card.bar:SetHeight(2)
    end
    local canvas = CreateFrame("Frame", nil, card)
    canvas:SetSize(Preview.CANVAS_W, Preview.CANVAS_H)
    canvas:SetScale(scale)
    canvas:SetPoint("CENTER", card, "CENTER", 0, 0)
    Utils.Pixel(canvas, "BACKGROUND", 0.047, 0.047, 0.051, 1):SetAllPoints()
    card.canvas = canvas
    return card
end

local function Build()
    if popup then
        return popup
    end
    popup = CreateFrame("Frame", "BetterGreatVaultNews", UIParent)
    popup:SetFrameStrata("DIALOG")
    popup:SetWidth(WIDTH)
    popup:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    popup:EnableMouse(true)
    if popup.SetClampedToScreen then
        popup:SetClampedToScreen(true)
    end
    Utils.Pixel(popup, "BACKGROUND", 0.055, 0.055, 0.062, 0.98):SetAllPoints()
    Utils.Border(popup, 0.24, 0.24, 0.27, 1)
    popup:Hide()

    popup.previews = {}
    for index, key in ipairs(PREVIEWS) do
        local featured = index == 2
        local preview = MakePreview(popup, featured and BIG or SMALL, featured)
        preview.key = key
        popup.previews[index] = preview
    end

    popup.kicker = Text(popup, "NormalSmall", 0.85, 0.65, 0.2)
    popup.title = Text(popup, "NormalLarge", 0.96, 0.96, 0.96)
    popup.body = Text(popup, "Highlight", 0.7, 0.7, 0.72)
    popup.points = {}
    for index = 1, 3 do
        local point = {}
        point.square = Utils.Pixel(popup, "ARTWORK", 0.85, 0.65, 0.2, 1)
        point.square:SetSize(6, 6)
        point.text = Utils.FontString(popup, "OVERLAY", "Highlight")
        point.text:SetJustifyH("LEFT")
        point.text:SetWordWrap(true)
        point.text:SetTextColor(0.9, 0.9, 0.9)
        popup.points[index] = point
    end
    popup.gotIt = Utils.CreateFlatButton(popup, 160, 30)

    popup.gotIt:SetScript("OnClick", Utils.Protect("news", function()
        News.Close()
    end))
    -- Escape closes it first, the settings staying open (a second Escape closes them): shown, it
    -- takes the keyboard, passes every other key on and keeps Escape, as the loot table does. In
    -- combat an addon can't change what a frame keeps (SetPropagateKeyboardInput is restricted),
    -- so shown then it leaves the keyboard alone and Escape closes it with the settings, through
    -- the game's list below.
    popup:EnableKeyboard(false)
    popup:SetScript("OnShow", function(self)
        if InCombat() then
            self:EnableKeyboard(false)
        else
            self:SetPropagateKeyboardInput(true)
            self:EnableKeyboard(true)
        end
    end)
    popup:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombat() then
            self:SetPropagateKeyboardInput(false)
            self:Hide()
        end
    end)
    if type(UISpecialFrames) == "table" then
        table.insert(UISpecialFrames, "BetterGreatVaultNews")
    end
    return popup
end

-- The text in the chosen language, the accent from the settings, then everything placed from the
-- top: the previews, the kicker, title, body, the three points and the button.
local function Fill()
    local accent = Utils.AccentColor()
    local r, g, b = accent[1], accent[2], accent[3]
    popup.kicker:SetText(Utils.Upper(L["New in Better Great Vault"]))
    popup.kicker:SetTextColor(r, g, b)
    popup.title:SetText(L["Settings that show where they apply"])
    popup.body:SetText(L["Rest the pointer on an option in the settings, and a small sketch of the addon shows what it changes, lit in your accent color."])
    local points = {
        L["The vault, the loot table, the minimap and the chat, with the changed part lit"],
        L["The opening options play your opening animation right in the sketch"],
        L["Pointing changes nothing: a click does, and the sketch follows it"],
    }
    popup.gotIt:SetText(L["Got it"])

    local inner = WIDTH - PAD * 2
    local y = PAD
    local tallest = 0
    for _, preview in ipairs(popup.previews) do
        tallest = math.max(tallest, preview:GetHeight() or 0)
    end
    local gap = 10
    local rowW = 0
    for _, preview in ipairs(popup.previews) do
        rowW = rowW + (preview:GetWidth() or 0)
    end
    rowW = rowW + gap * (#popup.previews - 1)
    local x = (WIDTH - rowW) / 2
    for _, preview in ipairs(popup.previews) do
        preview:ClearAllPoints()
        preview:SetPoint("TOPLEFT", popup, "TOPLEFT", x, -(y + (tallest - (preview:GetHeight() or 0)) / 2))
        x = x + (preview:GetWidth() or 0) + gap
        if preview.bar then
            preview.bar:SetVertexColor(r, g, b, 1)
        end
        if BGV.SettingsPreview and BGV.SettingsPreview.Draw then
            BGV.SettingsPreview.Draw(preview.canvas, preview.key, accent)
        end
    end
    y = y + tallest + 20

    local function Height(region, fallback)
        local height = region:GetStringHeight()
        return Utils.IsUsableNumber(height) and height > 0 and height or fallback
    end
    for _, text in ipairs({ popup.kicker, popup.title, popup.body }) do
        text:ClearAllPoints()
        text:SetWidth(inner)
        text:SetPoint("TOP", popup, "TOP", 0, -y)
        y = y + Height(text, 14) + (text == popup.kicker and 6 or 10)
    end
    y = y + 4
    for index, point in ipairs(popup.points) do
        point.square:SetVertexColor(r, g, b, 1)
        point.text:SetText(points[index])
        point.text:SetWidth(inner - 18)
        point.square:ClearAllPoints()
        point.square:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD + 2, -(y + 5))
        point.text:ClearAllPoints()
        point.text:SetPoint("TOPLEFT", popup, "TOPLEFT", PAD + 18, -y)
        y = y + Height(point.text, 14) + 8
    end
    y = y + 14
    popup.gotIt:ClearAllPoints()
    popup.gotIt:SetPoint("TOP", popup, "TOP", 0, -y)
    y = y + 30 + PAD
    popup:SetHeight(y)
end

-- Shows the news, when asked for.
function News.Show()
    Build()
    -- shown unseen first: text is measured right only on a shown frame
    popup:SetAlpha(0)
    popup:Show()
    Fill()
    popup:SetAlpha(1)
end
News.Show = Utils.Protect("news", News.Show)

function News.Close()
    if popup then
        popup:Hide()
    end
end
