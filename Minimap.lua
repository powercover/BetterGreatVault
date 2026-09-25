local _, BGV = ...

BGV.Minimap = {}

local ICON = "Interface\\AddOns\\BetterGreatVault\\Icon"
local RADIUS = 80
local category

local function ShowMinimap()
    return not BetterGreatVaultDB or BetterGreatVaultDB.showMinimap ~= false
end

local function LoadVaultUI()
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" and C_AddOns.IsAddOnLoaded("Blizzard_WeeklyRewards") then
        return
    end
    if type(IsAddOnLoaded) == "function" and IsAddOnLoaded("Blizzard_WeeklyRewards") then
        return
    end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn("Blizzard_WeeklyRewards")
    elseif type(LoadAddOn) == "function" then
        LoadAddOn("Blizzard_WeeklyRewards")
    end
end

function BGV.Minimap.ToggleVault()
    LoadVaultUI()
    if WeeklyRewardsFrame and type(WeeklyRewardsFrame.IsShown) == "function" and WeeklyRewardsFrame:IsShown() then
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
    if SettingsPanel and type(SettingsPanel.IsShown) == "function" and SettingsPanel:IsShown() then
        if type(HideUIPanel) == "function" then
            HideUIPanel(SettingsPanel)
        else
            SettingsPanel:Hide()
        end
        return
    end
    if not (Settings and type(Settings.OpenToCategory) == "function" and category and type(category.GetID) == "function") then
        return
    end
    Settings.OpenToCategory(category:GetID())
end

local button = CreateFrame("Button", "BetterGreatVaultMinimapButton", Minimap)
button:SetSize(31, 31)
button:SetFrameStrata("MEDIUM")
button:SetFrameLevel(8)
button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
button:RegisterForClicks("AnyUp")
button:RegisterForDrag("LeftButton")
button:Hide()

local border = button:CreateTexture(nil, "OVERLAY")
border:SetSize(53, 53)
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetPoint("TOPLEFT")

local icon = button:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", 0, 1)
icon:SetTexture(ICON)

local function Place()
    local angle = BetterGreatVaultDB and BetterGreatVaultDB.minimapAngle or 220
    local rad = math.rad(angle)
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * RADIUS, math.sin(rad) * RADIUS)
end

function BGV.Minimap.Apply()
    if ShowMinimap() then
        Place()
        button:Show()
    else
        button:Hide()
    end
end

button:SetScript("OnClick", function(self, mouseButton)
    if self.dragged then
        self.dragged = false
        return
    end
    if mouseButton == "RightButton" then
        BGV.Minimap.ToggleSettings()
    else
        BGV.Minimap.ToggleVault()
    end
end)

button:SetScript("OnDragStart", function(self)
    self.dragging = true
    self.dragged = true
end)

button:SetScript("OnDragStop", function(self)
    self.dragging = false
end)

button:SetScript("OnUpdate", function(self)
    if not self.dragging or not Minimap then
        return
    end
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    if not mx or not scale or scale == 0 then
        return
    end
    local angle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
    BetterGreatVaultDB.minimapAngle = angle
    Place()
end)

button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Better Great Vault")
    GameTooltip:AddLine("Left-click: Toggle the Great Vault", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Toggle addon settings", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

function BGV.Minimap.RegisterSettings()
    if category or not (Settings and type(Settings.RegisterVerticalLayoutCategory) == "function") then
        BGV.Minimap.Apply()
        return
    end

    category = Settings.RegisterVerticalLayoutCategory("Better Great Vault")
    local setting = Settings.RegisterProxySetting(
        category,
        "BGV_SHOW_MINIMAP",
        Settings.VarType.Boolean,
        "Show minimap button",
        true,
        function()
            return ShowMinimap()
        end,
        function(value)
            BetterGreatVaultDB.showMinimap = value and true or false
            BGV.Minimap.Apply()
        end
    )
    Settings.CreateCheckbox(category, setting, "Show a minimap button. Left-click toggles the Great Vault. Right-click toggles these settings.")
    local animations = Settings.RegisterProxySetting(
        category,
        "BGV_DISABLE_ANIMATIONS",
        Settings.VarType.Boolean,
        "Disable animations",
        false,
        function()
            return BetterGreatVaultDB and BetterGreatVaultDB.disableAnimations == true
        end,
        function(value)
            BetterGreatVaultDB.disableAnimations = value and true or false
            if BGV.UI and type(BGV.UI.RefreshOpenFrame) == "function" then
                BGV.UI.RefreshOpenFrame()
            end
        end
    )
    Settings.CreateCheckbox(category, animations, "Keep the vault slots closed. Mouseover shows the short caption only, with no reel.")

    local function RefreshAccent()
        if BGV.UI and type(BGV.UI.RefreshOpenFrame) == "function" then
            BGV.UI.RefreshOpenFrame()
        end
    end

    local function AddAccentSettings()
        if type(CreateSettingsListSectionHeaderInitializer) == "function" then
            local layout = SettingsPanel and SettingsPanel.GetLayout and SettingsPanel:GetLayout(category)
            if layout and type(layout.AddInitializer) == "function" then
                layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Accent color"))
            end
        end

        local function SpecAccentOn()
            return not BetterGreatVaultDB or BetterGreatVaultDB.useSpecAccent ~= false
        end

        local function AlignSwatch(control)
            local swatch = control and control.ColorSwatch
            if not swatch then
                return
            end
            swatch:SetSize(120, 18)
            swatch:ClearAllPoints()
            swatch:SetPoint("LEFT", control, "CENTER", -80, 0)
            local color = swatch.Color
            if color then
                local r, g, b, a = 0.85, 0.65, 0.2, 1
                if color.GetVertexColor then
                    r, g, b, a = color:GetVertexColor()
                end
                color:SetTexture("Interface\\Buttons\\WHITE8X8")
                color:SetVertexColor(r, g, b, a or 1)
                color:ClearAllPoints()
                color:SetPoint("TOPLEFT", swatch, "TOPLEFT", 1, -1)
                color:SetPoint("BOTTOMRIGHT", swatch, "BOTTOMRIGHT", -1, 1)
            end
            if swatch.GetRegions then
                for _, region in ipairs({ swatch:GetRegions() }) do
                    if region ~= color and region.Hide and region.GetObjectType and region:GetObjectType() == "Texture" and not region.bgvEdge then
                        region:Hide()
                    end
                end
            end
            if not swatch.bgvEdges then
                swatch.bgvEdges = true
                local function Edge(anchor1, relative1, x1, y1, anchor2, relative2, x2, y2, horizontal)
                    local line = swatch:CreateTexture(nil, "OVERLAY")
                    line:SetTexture("Interface\\Buttons\\WHITE8X8")
                    line:SetVertexColor(0.72, 0.72, 0.72, 1)
                    line:SetPoint(anchor1, swatch, relative1, x1, y1)
                    line:SetPoint(anchor2, swatch, relative2, x2, y2)
                    if horizontal then
                        line:SetHeight(1)
                    else
                        line:SetWidth(1)
                    end
                    line.bgvEdge = true
                    return line
                end
                Edge("TOPLEFT", "TOPLEFT", 0, 0, "TOPRIGHT", "TOPRIGHT", 0, 0, true)
                Edge("BOTTOMLEFT", "BOTTOMLEFT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, true)
                Edge("TOPLEFT", "TOPLEFT", 0, 0, "BOTTOMLEFT", "BOTTOMLEFT", 0, 0, false)
                Edge("TOPRIGHT", "TOPRIGHT", 0, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", 0, 0, false)
            end
        end

        local function SyncSwatch()
            local control = BGV.accentSwatch
            if not control then
                return
            end
            local enabled = not SpecAccentOn()
            local text = control.Text
            if text and text.SetTextColor then
                if enabled and NORMAL_FONT_COLOR then
                    text:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
                elseif GRAY_FONT_COLOR then
                    text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
                else
                    text:SetTextColor(enabled and 1 or 0.5, enabled and 0.82 or 0.5, enabled and 0 or 0.5)
                end
            end
            local swatch = control.ColorSwatch
            if swatch then
                if swatch.SetEnabled then
                    swatch:SetEnabled(enabled)
                end
                swatch:SetAlpha(enabled and 1 or 0.35)
                if swatch.SetDesaturated then
                    swatch:SetDesaturated(not enabled)
                end
            end
            if control.Tooltip and control.Tooltip.EnableMouse then
                control.Tooltip:EnableMouse(enabled)
            end
            AlignSwatch(control)
        end

        local function ChannelByte(channel)
            local n = math.floor((channel or 0) * 255 + 0.5)
            if n < 0 then
                n = 0
            elseif n > 255 then
                n = 255
            end
            return n
        end

        local function ColorToHex(r, g, b)
            return string.format("FF%02X%02X%02X", ChannelByte(r), ChannelByte(g), ChannelByte(b))
        end

        local function HexToColor(value)
            if type(value) ~= "string" then
                return 0.85, 0.65, 0.2
            end
            local hex = value
            if #hex == 8 then
                hex = hex:sub(3)
            end
            if #hex ~= 6 then
                return 0.85, 0.65, 0.2
            end
            local r = tonumber(hex:sub(1, 2), 16)
            local g = tonumber(hex:sub(3, 4), 16)
            local b = tonumber(hex:sub(5, 6), 16)
            if not r or not g or not b then
                return 0.85, 0.65, 0.2
            end
            return r / 255, g / 255, b / 255
        end

        local function SavedAccent()
            local saved = BetterGreatVaultDB and BetterGreatVaultDB.accentColor
            local r = type(saved) == "table" and (saved.r or saved[1]) or 0.85
            local g = type(saved) == "table" and (saved.g or saved[2]) or 0.65
            local b = type(saved) == "table" and (saved.b or saved[3]) or 0.2
            return ColorToHex(r, g, b)
        end

        local customAccent = Settings.RegisterProxySetting(
            category,
            "BGV_ACCENT_COLOR",
            nil,
            "Custom",
            SavedAccent(),
            SavedAccent,
            function(value)
                local r, g, b = HexToColor(value)
                BetterGreatVaultDB.accentColor = { r = r, g = g, b = b }
                RefreshAccent()
            end
        )

        local specAccent = Settings.RegisterProxySetting(
            category,
            "BGV_SPEC_ACCENT",
            Settings.VarType.Boolean,
            "Class specialization",
            true,
            SpecAccentOn,
            function(value)
                BetterGreatVaultDB.useSpecAccent = value and true or false
                SyncSwatch()
                RefreshAccent()
            end
        )
        Settings.CreateCheckbox(category, specAccent, "Use your specialization color for the vertical line. Uncheck this to pick a custom color.")

        local swatch
        if type(Settings.CreateColorSwatch) == "function" then
            swatch = Settings.CreateColorSwatch(category, customAccent, "Color used for the vertical line when class specialization is off.")
        elseif type(Settings.CreateSettingInitializer) == "function" and SettingsPanel and type(SettingsPanel.GetLayout) == "function" then
            local data = Settings.CreateSettingInitializerData(customAccent, nil, "Color used for the vertical line when class specialization is off.")
            swatch = Settings.CreateSettingInitializer("SettingsColorSwatchControlTemplate", data)
            local layout = SettingsPanel:GetLayout(category)
            if layout and swatch then
                layout:AddInitializer(swatch)
            end
        end
        if swatch then
            swatch.bgvCustomAccent = true
            swatch.IsNewTagShown = function()
                return false
            end
            swatch.MarkSettingAsSeen = function()
            end
        end
        if type(hooksecurefunc) == "function" and SettingsColorSwatchControlMixin and not SettingsColorSwatchControlMixin.bgvAccentHook then
            SettingsColorSwatchControlMixin.bgvAccentHook = true
            hooksecurefunc(SettingsColorSwatchControlMixin, "Init", function(self, initializer)
                if not initializer or not initializer.bgvCustomAccent then
                    return
                end
                BGV.accentSwatch = self
                self:HookScript("OnShow", SyncSwatch)
                if self.ColorSwatch and self.ColorSwatch.SetColor and not self.ColorSwatch.bgvWideHook then
                    self.ColorSwatch.bgvWideHook = true
                    hooksecurefunc(self.ColorSwatch, "SetColor", function()
                        AlignSwatch(self)
                    end)
                end
                SyncSwatch()
            end)
        end
    end

    local ok, err = pcall(AddAccentSettings)
    if not ok then
        BGV.lastError = err
        if DEFAULT_CHAT_FRAME then
            DEFAULT_CHAT_FRAME:AddMessage("|cffff2020Better Great Vault:|r accent color option failed: " .. tostring(err))
        end
    end
    Settings.RegisterAddOnCategory(category)
    BGV.Minimap.Apply()
end
