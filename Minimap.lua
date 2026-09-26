local _, BGV = ...

BGV.Minimap = {}

local ICON = "Interface\\AddOns\\BetterGreatVault\\Icon"
local RADIUS = 80

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
    if BGV.Settings and type(BGV.Settings.Toggle) == "function" then
        BGV.Settings.Toggle()
    end
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
    elseif mouseButton == "MiddleButton" then
        if BGV.LootTable and type(BGV.LootTable.Toggle) == "function" then
            BGV.LootTable.Toggle()
        end
    else
        BGV.Minimap.ToggleVault()
    end
end)

button:SetScript("OnDragStart", function(self)
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
        if not mx or not scale or scale == 0 then
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
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Better Great Vault")
    GameTooltip:AddLine("Left-click: Toggle the Great Vault", 1, 1, 1)
    GameTooltip:AddLine("Middle-click: Possible loot", 1, 1, 1)
    GameTooltip:AddLine("Right-click: Toggle addon settings", 1, 1, 1)
    GameTooltip:Show()
end)

button:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

function BGV.Minimap.RegisterSettings()
    BGV.Minimap.Apply()
    if BGV.Settings and type(BGV.Settings.RegisterBridge) == "function" then
        BGV.Settings.RegisterBridge()
    end
end
