local addonName, BGV = ...

BGV.Settings = {}

local L = BGV.L

local FRAME_W = 720
local FRAME_H = 460
local LEFT_W = 188
local PAD = 22
local TEXT_W = FRAME_W - LEFT_W - PAD * 2 - 16
local BUTTON_H = 24

-- Where to find the addon online, listed in About. A link without an address yet shows "Coming
-- soon"; set its `url` once the page exists.
BGV.Settings.LINKS = {
    { name = "CurseForge" },
    { name = "Wago" },
}

local panel
local scroll
local child
local links = {}
local sections = {}
local widgets = {}
local scrollAnim
local bridgeCategory
local contentHeight
local layout = {}

local function DB()
    return BetterGreatVaultDB
end

-- The panel's own accents (selection bar, heading rules, checkbox fills) follow the addon's
-- accent color, so the choice made here shows right away.
local accentTextures = {}

local function Accent(texture, alpha)
    accentTextures[#accentTextures + 1] = { texture = texture, alpha = alpha or 1 }
    return texture
end

local function PaintAccent()
    local color = BGV.Utils.AccentColor()
    for _, item in ipairs(accentTextures) do
        item.texture:SetVertexColor(color[1], color[2], color[3], item.alpha)
    end
end

local function RefreshAccent()
    PaintAccent()
    local function Go()
        if BGV.UI and type(BGV.UI.RefreshOpenFrame) == "function" then
            BGV.UI.RefreshOpenFrame()
        end
        if BGV.LootTable and type(BGV.LootTable.RefreshStyle) == "function" then
            BGV.LootTable.RefreshStyle()
        end
    end
    Go()
    if C_Timer and type(C_Timer.After) == "function" then
        C_Timer.After(0, Go)
    end
end

BGV.Settings.RefreshAccent = RefreshAccent

local function SpecAccentOn()
    local saved = DB()
    return not saved or saved.useSpecAccent ~= false
end

local function Call(func, ...)
    if type(func) == "function" then
        return func(...)
    end
end

local Pixel = BGV.Utils.Pixel

local function Edge(parent, target, point1, rel1, x1, y1, point2, rel2, x2, y2, horizontal)
    local line = Pixel(parent, "BORDER", 0.22, 0.22, 0.24, 1)
    line:SetPoint(point1, target or parent, rel1, x1, y1)
    line:SetPoint(point2, target or parent, rel2, x2, y2)
    if horizontal then
        line:SetHeight(1)
    else
        line:SetWidth(1)
    end
    return line
end

local function BoxBorder(parent, target)
    Edge(parent, target, "TOPLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, 0, true)
    Edge(parent, target, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, true)
    Edge(parent, target, "TOPLEFT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, false)
    Edge(parent, target, "TOPRIGHT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, false)
end

local function SelectLink(id)
    for index, link in ipairs(links) do
        local selected = index == id
        link.selected = selected
        if selected then
            link.label:SetTextColor(0.96, 0.96, 0.96)
        else
            link.label:SetTextColor(0.46, 0.46, 0.48)
        end
        link.bar:SetShown(selected)
    end
end

local function CategoryFromScroll()
    if not scroll then
        return
    end
    local offset = scroll:GetVerticalScroll()
    local id = 1
    for index = #sections, 1, -1 do
        if offset + 28 >= sections[index] then
            id = index
            break
        end
    end
    SelectLink(id)
end

local function ScrollTo(id)
    if not scroll or not sections[id] then
        return
    end
    SelectLink(id)
    local target = sections[id]
    local maxScroll = scroll:GetVerticalScrollRange()
    if target > maxScroll then
        target = maxScroll
    end
    if target < 0 then
        target = 0
    end
    scrollAnim.from = scroll:GetVerticalScroll()
    scrollAnim.to = target
    scrollAnim.t = 0
    scrollAnim.play = true
end

-- A link in the left menu, to a section of the page. `bottom` pins it to the bottom of the menu.
local function MakeLink(parent, text, id, bottom)
    local link = CreateFrame("Button", nil, parent)
    link:SetSize(LEFT_W - 28, 28)
    if bottom then
        link:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 18, 16)
    else
        link:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -78 - (id - 1) * 32)
    end
    link.id = id
    link.bottom = bottom

    local bar = Accent(Pixel(link, "ARTWORK", 0.85, 0.65, 0.2, 1))
    bar:SetSize(2, 14)
    bar:SetPoint("LEFT", link, "LEFT", 0, 0)
    bar:Hide()
    link.bar = bar

    local label = BGV.Utils.FontString(link, "OVERLAY", "Highlight")
    label:SetPoint("LEFT", link, "LEFT", 12, 0)
    label:SetJustifyH("LEFT")
    label:SetText(text)
    link.label = label

    local underline = Pixel(link, "OVERLAY", 0.96, 0.96, 0.96, 0.7)
    underline:SetHeight(1)
    underline:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
    underline:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -1)
    underline:Hide()

    link:SetScript("OnClick", function(self)
        ScrollTo(self.id)
    end)
    link:SetScript("OnEnter", function(self)
        self.label:SetTextColor(0.96, 0.96, 0.96)
        underline:Show()
    end)
    link:SetScript("OnLeave", function(self)
        underline:Hide()
        if not self.selected then
            self.label:SetTextColor(0.46, 0.46, 0.48)
        end
    end)

    links[id] = link
    return link
end

local function MakeHeader(parent, text, section)
    local header = BGV.Utils.FontString(parent, "OVERLAY", "NormalLarge")
    header:SetJustifyH("LEFT")
    header:SetText(text)
    header:SetTextColor(0.96, 0.96, 0.96)
    local rule = Accent(Pixel(parent, "ARTWORK", 0.85, 0.65, 0.2, 0.9), 0.9)
    rule:SetSize(36, 2)
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    layout[#layout + 1] = { widget = header, x = PAD, height = 36, section = section }
    return header
end

-- A small heading for a group of options within a section.
local function MakeSubheader(parent, text)
    local label = BGV.Utils.FontString(parent, "OVERLAY", "NormalSmall")
    label:SetJustifyH("LEFT")
    label:SetText(BGV.Utils.Upper(text))
    label:SetTextColor(0.62, 0.62, 0.66)
    layout[#layout + 1] = { widget = label, x = PAD, height = 22 }
    return label
end

local function MakeGap(gap)
    layout[#layout + 1] = { gap = gap or 18 }
end

-- Help text: under a checkbox's label (default), `true` flush with the section's left edge, or a
-- number of steps in (2: under a nested checkbox's label).
local function MakeNote(parent, text, depth)
    local note = BGV.Utils.FontString(parent, "OVERLAY", "Disable")
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    note:SetText(text)
    note:SetTextColor(0.58, 0.58, 0.6)
    local x = PAD + 28
    if depth == true then
        x = PAD
    elseif type(depth) == "number" then
        x = PAD + 28 * depth
    end
    layout[#layout + 1] = { widget = note, x = x, note = true }
    return note
end

local function MakeParagraph(parent, text)
    local note = MakeNote(parent, text, true)
    note:SetFontObject(BGV.Utils.Font("Highlight"))
    note:SetTextColor(0.84, 0.84, 0.86)
    return note
end

-- `options`: indent (steps in, under another checkbox) and requires (a check that enables it).
local function MakeCheckbox(parent, label, getter, setter, options)
    options = options or {}
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(TEXT_W, 22)

    local box = Pixel(row, "BACKGROUND", 0.16, 0.16, 0.17, 1)
    box:SetSize(18, 18)
    box:SetPoint("LEFT", row, "LEFT", 0, 0)
    BoxBorder(row, box)

    local fill = Accent(Pixel(row, "ARTWORK", 0.85, 0.65, 0.2, 1))
    fill:SetSize(10, 10)
    fill:SetPoint("CENTER", box, "CENTER", 0, 0)
    fill:Hide()
    row.fill = fill

    local text = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(label)
    text:SetTextColor(0.92, 0.92, 0.92)
    row.label = text

    function row:Refresh()
        fill:SetShown(getter() and true or false)
        local enabled = not options.requires or options.requires()
        self:SetAlpha(enabled and 1 or 0.4)
        self:EnableMouse(enabled)
    end

    row:SetScript("OnClick", function(self)
        setter(not getter())
        self:Refresh()
    end)
    row:SetScript("OnEnter", function()
        text:SetTextColor(1, 1, 1)
    end)
    row:SetScript("OnLeave", function()
        text:SetTextColor(0.92, 0.92, 0.92)
    end)

    widgets[#widgets + 1] = row
    layout[#layout + 1] = { widget = row, x = PAD + 28 * (options.indent or 0), height = 26, stretch = true,
        resize = function(offset)
            row:SetHeight(22 + offset)
        end }
    return row
end

-- For something that can't be undone: the first click asks, and a second click within a few
-- seconds does it.
local function ConfirmClicks(button, text, question, action)
    local armed, token = false, 0
    local function Paint(r, g, b)
        local label = button:GetFontString()
        if label then
            label:SetTextColor(r, g, b)
        end
    end
    local function Disarm()
        armed = false
        button:SetText(text)
        Paint(1, 1, 1)
    end
    button:SetScript("OnClick", function()
        if armed then
            Disarm()
            action()
            return
        end
        armed = true
        token = token + 1
        local mine = token
        button:SetText(question)
        Paint(1, 0.38, 0.32)
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(4, function()
                if armed and token == mine then
                    Disarm()
                end
            end)
        end
    end)
    button:SetScript("OnHide", Disarm)
end

-- A row of flat buttons, each { text, width, onClick, confirm }. `options` as for checkboxes.
local function MakeButtons(parent, specs, options)
    options = options or {}
    local row = CreateFrame("Frame", nil, parent)
    row.buttons = {}
    for index, spec in ipairs(specs) do
        local button = BGV.Utils.CreateFlatButton(row, spec.width or 124, BUTTON_H)
        button.baseWidth = spec.width or 124
        button:SetText(spec.text)
        if spec.confirm then
            ConfirmClicks(button, spec.text, spec.confirm, spec.onClick)
        else
            button:SetScript("OnClick", spec.onClick)
        end
        row.buttons[index] = button
    end
    -- Wider and taller with the text size.
    local function Size(scale, height)
        local x = 0
        for _, button in ipairs(row.buttons) do
            local label = button:GetFontString()
            local textWidth = label and label:GetStringWidth() or 0
            local width = math.max(math.floor(button.baseWidth * scale + 0.5), math.ceil(textWidth + 24))
            button:SetSize(width, height)
            button:ClearAllPoints()
            button:SetPoint("LEFT", row, "LEFT", x, 0)
            x = x + width + 8
        end
        row:SetSize(math.max(1, x - 8), height)
    end
    Size(1, BUTTON_H)
    if options.requires then
        function row:Refresh()
            local enabled = options.requires()
            self:SetAlpha(enabled and 1 or 0.4)
            for _, button in ipairs(self.buttons) do
                button:EnableMouse(enabled)
            end
        end
        widgets[#widgets + 1] = row
    end
    layout[#layout + 1] = { widget = row, x = PAD + 28 * (options.indent or 0), height = BUTTON_H + 10,
        resize = function(offset, scale10)
            Size(scale10, BUTTON_H + offset)
        end }
    return row
end

-- A slider over whole steps from `min` to `max`, the default (0) marked on it. The stretch
-- between the default and the value is drawn in the accent color. spec: { min, max, getter,
-- setter, format }.
local SLIDER_W = 220
local THUMB_W = 10

local function MakeSlider(parent, spec)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TEXT_W, 28)
    local slider = CreateFrame("Slider", nil, row)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(SLIDER_W, 20)
    slider:SetPoint("LEFT", row, "LEFT", 0, 0)
    slider:SetMinMaxValues(spec.min, spec.max)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then
        slider:SetObeyStepOnDrag(true)
    end
    slider:EnableMouse(true)
    slider:EnableMouseWheel(true)
    local function X(value)
        return THUMB_W / 2 + (value - spec.min) / (spec.max - spec.min) * (SLIDER_W - THUMB_W)
    end
    local track = Pixel(slider, "BACKGROUND", 0.26, 0.26, 0.28, 1)
    track:SetHeight(4)
    track:SetPoint("LEFT", slider, "LEFT", 0, 0)
    track:SetPoint("RIGHT", slider, "RIGHT", 0, 0)
    for step = spec.min, spec.max do
        local tick = Pixel(slider, "BORDER", 0.34, 0.34, 0.38, 1)
        tick:SetSize(1, step == 0 and 12 or 6)
        tick:SetPoint("CENTER", slider, "LEFT", X(step), 0)
    end
    local fill = Accent(Pixel(slider, "ARTWORK", 1, 1, 1, 1))
    fill:SetHeight(4)
    local thumb = slider:CreateTexture(nil, "OVERLAY")
    thumb:SetTexture("Interface\\Buttons\\WHITE8X8")
    thumb:SetSize(THUMB_W, 18)
    Accent(thumb)
    slider:SetThumbTexture(thumb)
    local value = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
    value:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    row.slider, row.value = slider, value

    local quiet = false
    local function Paint(current)
        local from, to = X(0), X(current)
        fill:ClearAllPoints()
        fill:SetPoint("LEFT", slider, "LEFT", math.min(from, to), 0)
        fill:SetWidth(math.max(1, math.abs(to - from)))
        fill:SetShown(current ~= 0)
        value:SetText(spec.format(current))
    end
    slider:SetScript("OnValueChanged", function(_, raw)
        local current = math.floor(raw + 0.5)
        Paint(current)
        if not quiet and current ~= spec.getter() then
            spec.setter(current)
        end
    end)
    slider:SetScript("OnMouseWheel", function(self, delta)
        local current = math.floor(self:GetValue() + 0.5)
        self:SetValue(math.max(spec.min, math.min(spec.max, current + delta)))
    end)
    function row:Refresh()
        quiet = true
        slider:SetValue(spec.getter())
        quiet = false
        Paint(spec.getter())
    end
    widgets[#widgets + 1] = row
    layout[#layout + 1] = { widget = row, x = PAD + 4, height = 30, stretch = true }
    return row
end

local function AccentRGB()
    local saved = DB() and DB().accentColor
    local r = type(saved) == "table" and (saved.r or saved[1]) or 0.85
    local g = type(saved) == "table" and (saved.g or saved[2]) or 0.65
    local b = type(saved) == "table" and (saved.b or saved[3]) or 0.2
    return r, g, b
end

local function MakeColorRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TEXT_W, 22)

    local label = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
    label:SetPoint("LEFT", row, "LEFT", 28, 0)
    label:SetText(L["Custom"])
    label:SetTextColor(0.92, 0.92, 0.92)

    local swatch = CreateFrame("Button", nil, row)
    swatch:SetSize(168, 18)
    swatch:SetPoint("LEFT", label, "RIGHT", 16, 0)

    local color = Pixel(swatch, "ARTWORK", 0.85, 0.65, 0.2, 1)
    color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
    color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
    BoxBorder(swatch, swatch)

    local function Paint()
        local r, g, b = AccentRGB()
        color:SetVertexColor(r, g, b, 1)
        local enabled = not SpecAccentOn()
        label:SetTextColor(enabled and 0.92 or 0.42, enabled and 0.92 or 0.42, enabled and 0.92 or 0.44)
        swatch:SetAlpha(enabled and 1 or 0.35)
        swatch:EnableMouse(enabled)
    end

    local function ApplyColor(r, g, b)
        DB().accentColor = { r = r, g = g, b = b }
        Paint()
        RefreshAccent()
    end

    swatch:SetScript("OnClick", function()
        if SpecAccentOn() then
            return
        end
        local r, g, b = AccentRGB()
        local function Read()
            if ColorPickerFrame.GetColorRGB then
                return ColorPickerFrame:GetColorRGB()
            end
            return r, g, b
        end
        local info = {
            r = r,
            g = g,
            b = b,
            hasOpacity = false,
            swatchFunc = function()
                local nr, ng, nb = Read()
                ApplyColor(nr, ng, nb)
            end,
            cancelFunc = function()
                ApplyColor(r, g, b)
            end,
        }
        if ColorPickerFrame.SetupColorPickerAndShow then
            ColorPickerFrame:SetupColorPickerAndShow(info)
        else
            ColorPickerFrame.func = info.swatchFunc
            ColorPickerFrame.cancelFunc = info.cancelFunc
            ColorPickerFrame.hasOpacity = false
            ColorPickerFrame:SetColorRGB(r, g, b)
            ColorPickerFrame:Show()
        end
    end)

    function row:Refresh()
        Paint()
    end

    widgets[#widgets + 1] = row
    layout[#layout + 1] = { widget = row, x = PAD, height = 28, stretch = true,
        resize = function(offset)
            row:SetHeight(22 + offset)
        end }
    return row
end

local function Metadata(field, fallback)
    local get = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local value = type(get) == "function" and get(addonName, field) or nil
    if BGV.Utils.IsUsableString(value) then
        return value
    end
    return fallback
end

-- About: the emblem (its handle spinning, Utils.CreateEmblem), the addon's name, its version
-- and author.
local function MakeAboutCard(parent)
    local card = CreateFrame("Frame", nil, parent)
    card:SetHeight(52)
    local emblem = BGV.Utils.CreateEmblem(card, 48)
    emblem:SetPoint("LEFT", card, "LEFT", 0, 0)
    card.emblem = emblem
    local name = BGV.Utils.FontString(card, "OVERLAY", "NormalLarge")
    name:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 12, -7)
    name:SetText("Better Great Vault")
    name:SetTextColor(0.85, 0.65, 0.2)
    card.meta = BGV.Utils.FontString(card, "OVERLAY", "HighlightSmall")
    card.meta:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -6)
    card.meta:SetText(string.format(L["Version %s  •  by %s"], Metadata("Version", BGV.VERSION or "?"),
        Metadata("Author", BGV.AUTHOR or "?")))
    card.meta:SetTextColor(0.62, 0.62, 0.66)
    layout[#layout + 1] = { widget = card, x = PAD, height = 64, stretch = true,
        resize = function(offset)
            card:SetHeight(52 + offset)
        end }
    return card
end

-- A link in About. The game can't open a browser, so the address sits in a box to copy it from.
local function MakeLinkRow(parent, link)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(BUTTON_H)
    local name = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetText(link.name)
    name:SetTextColor(0.92, 0.92, 0.92)
    row.name = name
    if BGV.Utils.IsUsableString(link.url) then
        local box = CreateFrame("EditBox", nil, row)
        box:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        box:SetHeight(BUTTON_H)
        box:SetFontObject(BGV.Utils.Font("HighlightSmall"))
        box:SetAutoFocus(false)
        box:SetTextInsets(8, 8, 0, 0)
        box:SetText(link.url)
        box:SetCursorPosition(0)
        Pixel(box, "BACKGROUND", 0.12, 0.12, 0.135, 1):SetAllPoints()
        BoxBorder(box, box)
        box:SetScript("OnEditFocusGained", function(self)
            self:HighlightText()
        end)
        box:SetScript("OnEditFocusLost", function(self)
            self:HighlightText(0, 0)
            self:SetCursorPosition(0)
        end)
        -- Read only: typing puts the address back.
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then
                self:SetText(link.url)
                self:HighlightText()
            end
        end)
        box:SetScript("OnEscapePressed", box.ClearFocus)
        box:SetScript("OnEnterPressed", box.ClearFocus)
        row.box = box
    else
        local soon = BGV.Utils.FontString(row, "OVERLAY", "HighlightSmall")
        soon:SetText(L["Coming soon"])
        soon:SetTextColor(0.5, 0.5, 0.53)
        row.soon = soon
    end
    layout[#layout + 1] = { widget = row, x = PAD, height = BUTTON_H + 6, stretch = true,
        resize = function(offset, _, scale12)
            local x = math.floor(110 * scale12 + 0.5)
            row:SetHeight(BUTTON_H + offset)
            if row.box then
                row.box:SetPoint("LEFT", row, "LEFT", x, 0)
                row.box:SetHeight(BUTTON_H + offset)
            else
                row.soon:ClearAllPoints()
                row.soon:SetPoint("LEFT", row, "LEFT", x, 0)
            end
        end }
    return row
end

-- Opens one of the addon's windows from the settings. The settings close first, so the window
-- isn't left behind them.
local function Launch(open)
    BGV.Settings.Hide()
    open()
end

local function AnimatedSlots()
    local saved = DB()
    return not (saved and saved.disableAnimations == true)
end

-- How an unlocked slot opens (Case.lua): the specialization's style, one style, or a random one.
local function StyleLabel()
    local Case = BGV.Case
    local choice = Case.Choice()
    local name = Case.StyleName(choice)
    if choice == Case.SPEC then
        name = string.format(L["Match specialization (%s)"], Case.StyleName(Case.SpecStyle()))
    end
    return string.format(L["Opening style: %s"], name)
end

local function OpenStyleMenu(anchor, onPick)
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        return
    end
    local Case = BGV.Case
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        local function Radio(text, value)
            root:CreateRadio(text, function()
                return Case.Choice() == value
            end, function()
                onPick(value)
            end)
        end
        Radio(string.format(L["Match specialization (%s)"], Case.StyleName(Case.SpecStyle())), Case.SPEC)
        root:CreateDivider()
        for _, style in ipairs(Case.STYLES) do
            Radio(L[style.name], style.id)
        end
        root:CreateDivider()
        Radio(L["Random"], Case.RANDOM)
    end)
end

local function BuildGreatVault()
    MakeHeader(child, L["Great Vault"], 1)
    MakeCheckbox(child, L["Animated slots"], AnimatedSlots, function(value)
        DB().disableAnimations = not value
        RefreshAccent()
        BGV.Settings.Refresh()
    end)
    MakeNote(child, L["Hovering an unlocked slot opens its gates and spins a reel of the loot it can give. Off: the gates stay closed and the slot shows its caption."])
    local styleRow
    styleRow = MakeButtons(child, {
        { text = StyleLabel(), width = 240, onClick = function(self)
            OpenStyleMenu(self, function(value)
                DB().vaultStyle = value
                styleRow.buttons[1]:SetText(StyleLabel())
                BGV.Settings.Relayout()
            end)
        end },
    }, { indent = 1, requires = AnimatedSlots })
    -- The label names the specialization's style, which follows a spec change.
    local refresh = styleRow.Refresh
    function styleRow:Refresh()
        refresh(self)
        self.buttons[1]:SetText(StyleLabel())
    end
    MakeNote(child, L["How an unlocked slot opens when you point at it. Match specialization gives some specializations a style of their own, such as Frost Shatter for frost mages and frost death knights, and Vault Door to the rest. Random picks a different style each time."], 2)
    MakeCheckbox(child, L["Best-in-Slot tiers"], function()
        return BGV.Utils.ShowBisTiers()
    end, function(value)
        DB().showBisTiers = value and true or false
        RefreshAccent()
    end)
    MakeNote(child, L["Colors the reel's items by their Best-in-Slot tier for your loot spec (S, A, B, C, D, from Wowhead's guides), and shows the loot table's Tier column."])
    MakeCheckbox(child, L["Open the loot table from a slot"], function()
        local saved = DB()
        return not saved or saved.openLootTable ~= false
    end, function(value)
        DB().openLootTable = value and true or false
    end)
    MakeNote(child, L["Left-click an unlocked slot to list every reward it can give."])
    MakeCheckbox(child, L["Loot spec button"], function()
        local saved = DB()
        return not saved or saved.showLootSpecButton ~= false
    end, function(value)
        DB().showLootSpecButton = value and true or false
        RefreshAccent()
        if BGV.LootTable and type(BGV.LootTable.Invalidate) == "function" then
            BGV.LootTable.Invalidate()
        end
    end)
    MakeNote(child, L["On the Great Vault and the loot table: shows the spec your loot is filtered by, and lets you change it."])
    MakeCheckbox(child, L["Reward reminder"], function()
        local saved = DB()
        return not saved or saved.remindRewards ~= false
    end, function(value)
        DB().remindRewards = value and true or false
    end)
    MakeNote(child, L["At login, a line in chat when rewards are waiting in the Great Vault."])
end

local function ButtonShown()
    local saved = DB()
    return not saved or saved.showMinimap ~= false
end

local function BuildMinimap()
    MakeHeader(child, L["Minimap button"], 2)
    MakeCheckbox(child, L["Add to the addon compartment"], function()
        local saved = DB()
        return not saved or saved.useCompartment ~= false
    end, function(value)
        DB().useCompartment = value and true or false
        Call(BGV.Minimap and BGV.Minimap.ApplyCompartment)
    end)
    MakeNote(child, L["The addon compartment is Blizzard's addon menu on the minimap: the small button with a number. Better Great Vault is listed there with the same clicks as its minimap button. Needs a game restart after installing or updating the addon."])
    MakeCheckbox(child, L["Show minimap button"], ButtonShown, function(value)
        DB().showMinimap = value and true or false
        BGV.Minimap.Apply()
        BGV.Settings.Refresh()
    end)
    MakeNote(child, L["Left-click: Great Vault. Middle-click: loot table. Shift + middle-click: loot database. Right-click: these settings."])
    local nested = { indent = 1, requires = ButtonShown }
    MakeButtons(child, {
        { text = L["Reset position"], onClick = function()
            Call(BGV.Minimap and BGV.Minimap.ResetPosition)
        end },
    }, nested)
    MakeCheckbox(child, L["Show popup on mouseover"], function()
        local saved = DB()
        return not saved or saved.minimapPopup ~= false
    end, function(value)
        DB().minimapPopup = value and true or false
        BGV.Settings.Refresh()
    end, nested)
    MakeCheckbox(child, L["Show this week's slots"], function()
        local saved = DB()
        return not saved or saved.popupWeek ~= false
    end, function(value)
        DB().popupWeek = value and true or false
    end, { indent = 2, requires = function()
        local saved = DB()
        return ButtonShown() and (not saved or saved.minimapPopup ~= false)
    end })
    MakeNote(child, L["The popup's mini vault: each slot's item level, or its progress while locked."], 3)
    MakeCheckbox(child, L["Lock position"], function()
        local saved = DB()
        return saved and saved.lockMinimap == true
    end, function(value)
        DB().lockMinimap = value and true or false
    end, nested)
    MakeCheckbox(child, L["Unaffected by other addons"], function()
        local saved = DB()
        return saved and saved.independentMinimap == true
    end, function(value)
        DB().independentMinimap = value and true or false
        BGV.Minimap.Apply()
    end, nested)
    MakeNote(child, L["Keeps the button on the minimap when another addon gathers minimap buttons, such as EllesmereUI. A change takes full effect after a reload."], 2)
    MakeCheckbox(child, L["Fade out when not hovered"], function()
        local saved = DB()
        return saved and saved.fadeMinimap == true
    end, function(value)
        DB().fadeMinimap = value and true or false
        Call(BGV.Minimap and BGV.Minimap.UpdateFade)
    end, nested)
    MakeNote(child, L["The button stays faint until you point at it. It shows fully while rewards are waiting."], 2)
end

-- Text size: the addon's fonts, then everything that lays text out.
local function SetTextSize(value)
    DB().fontSize = value
    BGV.Utils.ApplyFontSize()
    if panel and panel.bgvFit then
        panel.bgvFit()
    end
    RefreshAccent()
end

-- The addon's language: the game's, or one picked here. The game has no Ukrainian version, so
-- Ukrainian is only reached this way. Text already drawn changes after a reload.
local languageInUse

local function LanguageLabel()
    local choice = BGV.Locale.Choice()
    if choice == "auto" then
        local game = type(GetLocale) == "function" and GetLocale() or "enUS"
        return string.format(L["Game language: %s"], BGV.Locale.Name(game))
    end
    return BGV.Locale.Name(choice)
end

local function OpenLanguageMenu(anchor, onPick)
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateRadio(L["Game language"], function()
            return BGV.Locale.Choice() == "auto"
        end, function()
            onPick("auto")
        end)
        for _, language in ipairs(BGV.Locale.LANGUAGES) do
            local code = language.code
            root:CreateRadio(language.name, function()
                return BGV.Locale.Choice() == code
            end, function()
                onPick(code)
            end)
        end
    end)
end

local function BuildLanguage()
    languageInUse = BGV.Locale.Current()
    MakeSubheader(child, L["Language"])
    local row
    row = MakeButtons(child, {
        { text = LanguageLabel(), width = 220, onClick = function(self)
            OpenLanguageMenu(self, function(code)
                DB().language = code
                row.buttons[1]:SetText(LanguageLabel())
                BGV.Settings.Refresh()
                BGV.Settings.Relayout()
            end)
        end },
    })
    MakeButtons(child, {
        { text = L["Reload now"], onClick = function()
            if type(ReloadUI) == "function" then
                ReloadUI()
            end
        end },
    }, { requires = function()
        return BGV.Locale.Current() ~= languageInUse
    end })
    MakeNote(child, L["The addon's language: the game's, or one picked here (the game has no Ukrainian version). A new language shows after the interface reloads."], true)
end

local function BuildAppearance()
    MakeHeader(child, L["Appearance"], 3)
    MakeSubheader(child, L["Text size"])
    MakeSlider(child, {
        min = -5,
        max = 5,
        getter = function()
            return BGV.Utils.FontOffset()
        end,
        setter = SetTextSize,
        format = function(value)
            if value == 0 then
                return L["Default"]
            end
            return value > 0 and ("+" .. value) or tostring(value)
        end,
    })
    MakeNote(child, L["Resizes the addon's text: on the Great Vault's slots, in the loot table, in the minimap popup and on this page."], true)
    MakeGap(8)
    BuildLanguage()
    MakeGap(8)
    MakeSubheader(child, L["Accent color"])
    MakeCheckbox(child, L["Class specialization"], SpecAccentOn, function(value)
        DB().useSpecAccent = value and true or false
        BGV.Settings.Refresh()
        RefreshAccent()
    end)
    MakeNote(child, L["Use your specialization's color for the addon's highlights. Uncheck this to pick your own."])
    MakeColorRow(child)
    MakeNote(child, L["Your color, used while class specialization is off."])
end

local function KeyText(command)
    if type(GetBindingKey) ~= "function" then
        return nil
    end
    local names = {}
    local key1, key2 = GetBindingKey(command)
    for _, key in ipairs({ key1 or false, key2 or false }) do
        if BGV.Utils.IsUsableString(key) then
            names[#names + 1] = type(GetBindingText) == "function" and GetBindingText(key) or key
        end
    end
    return #names > 0 and table.concat(names, ", ") or nil
end

local keyRows = {}

-- One of the addon's key bindings (Bindings.xml) and the keys bound to it.
local function MakeKeyRow(parent, text, command)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(22)
    local name = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
    name:SetPoint("LEFT", row, "LEFT", 0, 0)
    name:SetJustifyH("LEFT")
    name:SetText(text)
    name:SetTextColor(0.92, 0.92, 0.92)
    row.name = name
    local key = BGV.Utils.FontString(row, "OVERLAY", "HighlightSmall")
    key:SetJustifyH("LEFT")
    row.key = key
    keyRows[#keyRows + 1] = row
    function row:Refresh()
        local bound = KeyText(command)
        key:SetText(bound or L["Not bound"])
        if bound then
            key:SetTextColor(1, 1, 1)
        else
            key:SetTextColor(0.5, 0.5, 0.53)
        end
    end
    widgets[#widgets + 1] = row
    layout[#layout + 1] = { widget = row, x = PAD, height = 24, stretch = true,
        resize = function(offset, _, scale12)
            row:SetHeight(22 + offset)
            local x = math.floor(170 * scale12 + 0.5)
            for _, other in ipairs(keyRows) do
                x = math.max(x, math.ceil((other.name:GetStringWidth() or 0) + 20))
            end
            key:ClearAllPoints()
            key:SetPoint("LEFT", row, "LEFT", x, 0)
        end }
    return row
end

local function BuildKeyBindings()
    MakeHeader(child, L["Key bindings"], 4)
    MakeKeyRow(child, L["Great Vault"], "BETTERGREATVAULT_VAULT")
    MakeKeyRow(child, L["Loot table"], "BETTERGREATVAULT_LOOT")
    MakeKeyRow(child, L["Loot database"], "BETTERGREATVAULT_DATABASE")
    MakeKeyRow(child, L["Settings"], "BETTERGREATVAULT_SETTINGS")
    MakeGap(6)
    MakeButtons(child, {
        { text = L["Open Key Bindings"], width = 150, onClick = function()
            if Settings and Settings.KEYBINDINGS_CATEGORY_ID and type(Settings.OpenToCategory) == "function" then
                Settings.OpenToCategory(Settings.KEYBINDINGS_CATEGORY_ID)
            end
        end },
    })
    MakeNote(child, L["No keys are bound until you pick them. In the game's Key Bindings they're in the Better Great Vault section, and each key opens or closes its window."], true)
end

local function BuildTools()
    MakeHeader(child, L["Tools"], 5)
    MakeSubheader(child, L["Open"])
    MakeButtons(child, {
        { text = L["Great Vault"], onClick = function()
            Launch(function()
                Call(BGV.Minimap and BGV.Minimap.ShowVault)
            end)
        end },
        { text = L["Loot table"], onClick = function()
            Launch(function()
                Call(BGV.LootTable and BGV.LootTable.Show, nil)
            end)
        end },
        { text = L["Loot database"], onClick = function()
            Launch(function()
                Call(BGV.LootTable and BGV.LootTable.ShowDatabase)
            end)
        end },
    })
    MakeNote(child, L["The loot table lists what your unlocked slots can give. The loot database lists every reward the Great Vault can give this season, for any class."], true)

    MakeGap(10)
    MakeSubheader(child, L["Troubleshooting"])
    MakeCheckbox(child, L["Debug mode"], function()
        local saved = DB()
        return saved and saved.debug == true
    end, function(value)
        DB().debug = value and true or false
    end)
    MakeNote(child, L["Prints loading details to chat while the reels and the loot table load, for bug reports."])
    MakeButtons(child, {
        { text = L["Print vault data"], width = 140, onClick = function()
            Call(BGV.PrintVaultData)
        end },
        { text = L["Refresh vault data"], width = 140, onClick = function()
            Call(BGV.RefreshVault)
        end },
    })
    MakeNote(child, L["Print lists each Great Vault slot in chat, with its progress and reward item level. Refresh reads the Great Vault again."], true)
    MakeButtons(child, {
        { text = L["Print performance"], width = 140, onClick = function()
            Call(BGV.PrintPerformance)
        end },
    })
    MakeNote(child, L["Prints what the addon costs in chat: its CPU time a frame (from the game's addon profiler), its memory, how long it took to load, and its last slot animation and loot table load."], true)

    MakeGap(10)
    MakeSubheader(child, L["Reset"])
    MakeButtons(child, {
        { text = L["Reset settings"], width = 140, confirm = L["Click again to reset"], onClick = function()
            Call(BGV.ResetSettings)
        end },
    })
    MakeNote(child, L["Puts every option back to its default. What the addon learned about this season's rewards is kept."], true)

    MakeGap(10)
    MakeSubheader(child, L["Chat commands"])
    MakeNote(child, table.concat({
        "|cffe6e6e6/bgv status|r   " .. L["this week's Great Vault"],
        "|cffe6e6e6/bgv db|r   " .. L["loot database"],
        "|cffe6e6e6/bgv debug|r   " .. L["debug mode, and print the Great Vault's slots"],
        "|cffe6e6e6/bgv refresh|r   " .. L["read the Great Vault again"],
        "|cffe6e6e6/bgv perf|r   " .. L["what the addon costs: CPU, memory and animations"],
        "|cffe6e6e6/bgv reset|r   " .. L["reset settings"],
    }, "\n"), true)
end

local function BuildAbout()
    MakeHeader(child, L["About"], 6)
    MakeAboutCard(child)
    MakeParagraph(child, L["See what your Great Vault can give before you choose. Each slot shows the loot it can award at the exact item level, and the loot table and loot database let you browse every reward, for any class, to plan what to run next."])
    MakeGap(4)
    MakeSubheader(child, L["Links"])
    local copyable = false
    for _, link in ipairs(BGV.Settings.LINKS) do
        MakeLinkRow(child, link)
        copyable = copyable or BGV.Utils.IsUsableString(link.url)
    end
    if copyable then
        MakeNote(child, L["Click an address, then press Ctrl+C to copy it."], true)
    end
end

local function Build()
    if panel then
        return panel
    end

    scrollAnim = { play = false, from = 0, to = 0, t = 0 }

    panel = CreateFrame("Frame", "BetterGreatVaultSettings", UIParent)
    panel:SetSize(FRAME_W, FRAME_H)
    panel:EnableMouse(true)
    panel:Hide()

    local left = CreateFrame("Frame", nil, panel)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(LEFT_W)
    local leftBg = Pixel(left, "BACKGROUND", 0.05, 0.05, 0.06, 0.65)
    leftBg:SetAllPoints()

    local divider = Pixel(panel, "BORDER", 0.18, 0.18, 0.2, 1)
    divider:SetWidth(1)
    divider:SetPoint("TOP", left, "TOPRIGHT", 0, -1)
    divider:SetPoint("BOTTOM", left, "BOTTOMRIGHT", 0, 1)

    local title = BGV.Utils.FontString(left, "OVERLAY", "Normal")
    title:SetPoint("TOPLEFT", left, "TOPLEFT", 18, -22)
    title:SetJustifyH("LEFT")
    title:SetText("Better Great Vault")
    title:SetTextColor(0.85, 0.65, 0.2)

    MakeLink(left, L["Great Vault"], 1)
    MakeLink(left, L["Minimap button"], 2)
    MakeLink(left, L["Appearance"], 3)
    MakeLink(left, L["Key bindings"], 4)
    MakeLink(left, L["Tools"], 5)
    local aboutRule = Pixel(left, "ARTWORK", 1, 1, 1, 0.07)
    aboutRule:SetHeight(1)
    aboutRule:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 18, 52)
    aboutRule:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -18, 52)
    MakeLink(left, L["About"], 6, true)
    SelectLink(1)

    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 8)
    scroll:EnableMouseWheel(true)

    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(FRAME_W - LEFT_W)
    scroll:SetScrollChild(child)

    BuildGreatVault()
    MakeGap(18)
    BuildMinimap()
    MakeGap(18)
    BuildAppearance()
    MakeGap(18)
    BuildKeyBindings()
    MakeGap(18)
    BuildTools()
    MakeGap(18)
    BuildAbout()

    local function Fit()
        local offset = BGV.Utils.FontOffset()
        local scale10, scale12 = BGV.Utils.FontScale(10), BGV.Utils.FontScale(12)
        for id, link in ipairs(links) do
            link:SetHeight(28 + offset)
            if not link.bottom then
                link:ClearAllPoints()
                link:SetPoint("TOPLEFT", link:GetParent(), "TOPLEFT", 18, -78 - (id - 1) * (32 + offset))
            end
        end
        local width = scroll:GetWidth()
        if not width or width < 80 then
            width = panel:GetWidth() - LEFT_W
        end
        if not width or width < 80 then
            width = FRAME_W - LEFT_W
        end
        child:SetWidth(width)
        local y = 20
        for _, item in ipairs(layout) do
            if item.section then
                sections[item.section] = y - 20
                if sections[item.section] < 0 then
                    sections[item.section] = 0
                end
            end
            if item.gap and not item.widget then
                y = y + item.gap
            else
                item.widget:ClearAllPoints()
                item.widget:SetPoint("TOPLEFT", child, "TOPLEFT", item.x, -y)
                local height
                if item.note then
                    item.widget:SetWidth(math.max(140, width - item.x - 28))
                    height = item.widget:GetStringHeight()
                    if not height or height < 16 then
                        height = 16
                    end
                    height = height + 16
                else
                    if item.stretch then
                        item.widget:SetWidth(math.max(160, width - item.x - 24))
                    end
                    if item.resize then
                        item.resize(offset, scale10, scale12)
                    end
                    height = item.height + offset
                end
                y = y + height
            end
        end
        contentHeight = y
        local last = sections[#sections] or 0
        local extra = (panel:GetHeight() or FRAME_H) - (contentHeight - last)
        if extra < 40 then
            extra = 40
        end
        child:SetHeight(contentHeight + extra)
    end
    panel.bgvFit = Fit
    Fit()

    scroll:SetScript("OnMouseWheel", function(self, delta)
        scrollAnim.play = false
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local nextOffset = current - delta * 48
        if nextOffset < 0 then
            nextOffset = 0
        elseif nextOffset > maxScroll then
            nextOffset = maxScroll
        end
        self:SetVerticalScroll(nextOffset)
        CategoryFromScroll()
    end)
    scroll:SetScript("OnUpdate", function(self, elapsed)
        if not scrollAnim.play then
            return
        end
        scrollAnim.t = scrollAnim.t + elapsed
        local progress = scrollAnim.t / 0.22
        if progress >= 1 then
            progress = 1
            scrollAnim.play = false
        end
        progress = progress * progress * (3 - 2 * progress)
        self:SetVerticalScroll(scrollAnim.from + (scrollAnim.to - scrollAnim.from) * progress)
        CategoryFromScroll()
    end)

    panel:SetScript("OnShow", function(self)
        if self.bgvFit then
            self.bgvFit()
        end
        PaintAccent()
        BGV.Settings.Refresh()
        ScrollTo(1)
    end)
    panel:SetScript("OnSizeChanged", function(self)
        if self.bgvFit then
            self.bgvFit()
        end
    end)

    return panel
end

-- Lays the page out again (the text size changed).
function BGV.Settings.Relayout()
    if panel and panel.bgvFit then
        panel.bgvFit()
    end
end

function BGV.Settings.Refresh()
    if not panel then
        return
    end
    for _, widget in ipairs(widgets) do
        if widget.Refresh then
            widget:Refresh()
        end
    end
end

-- The keys shown under Key bindings follow changes made in the game's Key Bindings.
local bindingEvents = CreateFrame("Frame")
bindingEvents:RegisterEvent("UPDATE_BINDINGS")
bindingEvents:SetScript("OnEvent", function()
    BGV.Settings.Refresh()
end)

function BGV.Settings.Show()
    BGV.Settings.Toggle()
end

function BGV.Settings.Hide()
    if SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() then
        if type(HideUIPanel) == "function" then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
    end
end

function BGV.Settings.Toggle()
    Build()
    if not bridgeCategory then
        BGV.Settings.RegisterBridge()
    end
    if not (bridgeCategory and Settings and type(Settings.OpenToCategory) == "function") then
        return
    end
    local optionsOpen = SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown()
    local pageVisible = panel and type(panel.IsVisible) == "function" and panel:IsVisible()
    if optionsOpen and pageVisible then
        if type(HideUIPanel) == "function" then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
        return
    end
    if not optionsOpen and SettingsPanel then
        if type(ShowUIPanel) == "function" then
            ShowUIPanel(SettingsPanel)
        elseif type(SettingsPanel.Show) == "function" then
            SettingsPanel:Show()
        end
    end
    Settings.OpenToCategory(bridgeCategory:GetID())
end

function BGV.Settings.RegisterBridge()
    if bridgeCategory or not (Settings and type(Settings.RegisterCanvasLayoutCategory) == "function") then
        return
    end
    local frame = Build()
    bridgeCategory = Settings.RegisterCanvasLayoutCategory(frame, "Better Great Vault")
    Settings.RegisterAddOnCategory(bridgeCategory)
end
