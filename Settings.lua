local _, BGV = ...

BGV.Settings = {}

local FRAME_W = 720
local FRAME_H = 460
local LEFT_W = 188
local PAD = 22
local TEXT_W = FRAME_W - LEFT_W - PAD * 2 - 16

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

local function SpecAccentOn()
    local saved = DB()
    return not saved or saved.useSpecAccent ~= false
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

local function MakeLink(parent, text, id)
    local link = CreateFrame("Button", nil, parent)
    link:SetSize(LEFT_W - 28, 28)
    link:SetPoint("TOPLEFT", parent, "TOPLEFT", 18, -78 - (id - 1) * 32)
    link.id = id

    local bar = Accent(Pixel(link, "ARTWORK", 0.85, 0.65, 0.2, 1))
    bar:SetSize(2, 14)
    bar:SetPoint("LEFT", link, "LEFT", 0, 0)
    bar:Hide()
    link.bar = bar

    local label = link:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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
    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    header:SetJustifyH("LEFT")
    header:SetText(text)
    header:SetTextColor(0.96, 0.96, 0.96)
    local rule = Accent(Pixel(parent, "ARTWORK", 0.85, 0.65, 0.2, 0.9), 0.9)
    rule:SetSize(36, 2)
    rule:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    layout[#layout + 1] = { widget = header, x = PAD, height = 36, section = section }
    return header
end

local function MakeGap(gap)
    layout[#layout + 1] = { gap = gap or 18 }
end

local function MakeNote(parent, text)
    local note = parent:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    note:SetJustifyH("LEFT")
    note:SetJustifyV("TOP")
    note:SetWordWrap(true)
    note:SetText(text)
    note:SetTextColor(0.58, 0.58, 0.6)
    layout[#layout + 1] = { widget = note, x = PAD + 28, note = true }
    return note
end

local function MakeCheckbox(parent, label, y, getter, setter)
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

    local text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", box, "RIGHT", 10, 0)
    text:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    text:SetJustifyH("LEFT")
    text:SetWordWrap(true)
    text:SetText(label)
    text:SetTextColor(0.92, 0.92, 0.92)

    function row:Refresh()
        fill:SetShown(getter() and true or false)
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
    layout[#layout + 1] = { widget = row, x = PAD, height = 26, stretch = true }
    return row
end

local function AccentRGB()
    local saved = DB() and DB().accentColor
    local r = type(saved) == "table" and (saved.r or saved[1]) or 0.85
    local g = type(saved) == "table" and (saved.g or saved[2]) or 0.65
    local b = type(saved) == "table" and (saved.b or saved[3]) or 0.2
    return r, g, b
end

local function MakeColorRow(parent, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(TEXT_W, 22)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", row, "LEFT", 28, 0)
    label:SetText("Custom")
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
    layout[#layout + 1] = { widget = row, x = PAD, height = 28, stretch = true }
    return row
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

    local title = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", left, "TOPLEFT", 18, -22)
    title:SetJustifyH("LEFT")
    title:SetText("Better Great Vault")
    title:SetTextColor(0.85, 0.65, 0.2)

    MakeLink(left, "General", 1)
    MakeLink(left, "Accent color", 2)
    SelectLink(1)

    scroll = CreateFrame("ScrollFrame", nil, panel)
    scroll:SetPoint("TOPLEFT", left, "TOPRIGHT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -16, 8)
    scroll:EnableMouseWheel(true)

    child = CreateFrame("Frame", nil, scroll)
    child:SetWidth(FRAME_W - LEFT_W)
    scroll:SetScrollChild(child)

    MakeHeader(child, "General", 1)
    MakeCheckbox(child, "Open loot table", nil, function()
        local saved = DB()
        return not saved or saved.openLootTable ~= false
    end, function(value)
        DB().openLootTable = value and true or false
    end)
    MakeNote(child, "Left-click a completed slot to open the loot table with every reward that slot can give.")
    MakeCheckbox(child, "Show loot spec button", nil, function()
        local saved = DB()
        return not saved or saved.showLootSpecButton ~= false
    end, function(value)
        DB().showLootSpecButton = value and true or false
        RefreshAccent()
        if BGV.LootTable and type(BGV.LootTable.Invalidate) == "function" then
            BGV.LootTable.Invalidate()
        end
    end)
    MakeNote(child, "Shows the Loot Spec button on the Great Vault and the loot table, letting you see and change the spec loot is filtered by.")
    MakeCheckbox(child, "Show minimap button", nil, function()
        local saved = DB()
        return not saved or saved.showMinimap ~= false
    end, function(value)
        DB().showMinimap = value and true or false
        BGV.Minimap.Apply()
    end)
    MakeNote(child, "Left-click toggles the Great Vault. Right-click opens these settings.")
    MakeCheckbox(child, "Disable animations", nil, function()
        local saved = DB()
        return saved and saved.disableAnimations == true
    end, function(value)
        DB().disableAnimations = value and true or false
        RefreshAccent()
    end)
    MakeNote(child, "Keep the vault slots closed. Mouseover shows the short caption only, with no reel.")

    MakeGap(18)
    MakeHeader(child, "Accent color", 2)
    MakeCheckbox(child, "Class specialization", nil, SpecAccentOn, function(value)
        DB().useSpecAccent = value and true or false
        BGV.Settings.Refresh()
        RefreshAccent()
    end)
    MakeNote(child, "Use your specialization color for the vertical line. Uncheck this to pick a custom color.")
    MakeColorRow(child, nil)
    MakeNote(child, "Used for the vertical line when class specialization is off.")

    local function Fit()
        local width = scroll:GetWidth()
        if not width or width < 80 then
            width = panel:GetWidth() - LEFT_W
        end
        if not width or width < 80 then
            width = FRAME_W - LEFT_W
        end
        child:SetWidth(width)
        local noteWidth = width - (PAD + 28) - 28
        if noteWidth < 140 then
            noteWidth = 140
        end
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
                    item.widget:SetWidth(noteWidth)
                    height = item.widget:GetStringHeight()
                    if not height or height < 16 then
                        height = 16
                    end
                    height = height + 16
                else
                    if item.stretch then
                        item.widget:SetWidth(math.max(160, width - item.x - 24))
                    end
                    height = item.height
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
