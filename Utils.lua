local _, BGV = ...

BGV.Utils = {}

local Utils = BGV.Utils

local ADDON_NAME = "Better Great Vault"

function Utils.IsSecret(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    local ok, secret = pcall(issecretvalue, value)
    return ok and secret == true
end

function Utils.IsUsableNumber(value)
    return type(value) == "number" and not Utils.IsSecret(value)
end

function Utils.IsUsableString(value)
    return type(value) == "string" and value ~= "" and not Utils.IsSecret(value)
end

-- Selective boundary wrapper. Use around Blizzard calls that may be missing or restricted.
function Utils.Call(func, ...)
    if type(func) ~= "function" then
        return
    end

    local packed = { pcall(func, ...) }
    if not packed[1] then
        return
    end

    if Utils.IsSecret(packed[2]) then
        return
    end

    return unpack(packed, 2)
end

function Utils.CopyDefaults(target, defaults)
    if type(target) ~= "table" then
        target = {}
    end

    for key, value in pairs(defaults) do
        if target[key] == nil then
            if type(value) == "table" then
                target[key] = Utils.CopyDefaults({}, value)
            else
                target[key] = value
            end
        end
    end

    return target
end

function Utils.ThresholdType(name)
    local types = Enum and Enum.WeeklyRewardChestThresholdType
    if types and types[name] ~= nil then
        return types[name]
    end
end

function Utils.SameType(left, right)
    if not Utils.IsUsableNumber(left) or not Utils.IsUsableNumber(right) then
        return false
    end
    return left == right
end

function Utils.GlobalString(key, fallback)
    local value = _G[key]
    if type(value) == "string" and value ~= "" then
        return value
    end
    return fallback
end

-- One of the game's common words (RAIDS, DUNGEONS...) in the game's language; or the addon's
-- translation of `english` when the addon speaks another language than the game.
function Utils.GameText(global, english)
    if BGV.Locale and BGV.Locale.Foreign() then
        return BGV.L[english]
    end
    return Utils.GlobalString(global, BGV.L[english])
end

-- Difficulty names in the addon's language, for when it isn't the game's.
local DIFFICULTY_TEXT = {
    [1] = "Normal", [2] = "Heroic", [8] = "Mythic Keystone", [14] = "Normal", [15] = "Heroic",
    [16] = "Mythic", [17] = "Raid Finder", [23] = "Mythic",
}

function Utils.DifficultyName(difficultyID)
    if not Utils.IsUsableNumber(difficultyID) or difficultyID <= 0 then
        return nil
    end
    if DIFFICULTY_TEXT[difficultyID] and BGV.Locale and BGV.Locale.Foreign() then
        return BGV.L[DIFFICULTY_TEXT[difficultyID]]
    end

    if DifficultyUtil and type(DifficultyUtil.GetDifficultyName) == "function" then
        local name = Utils.Call(DifficultyUtil.GetDifficultyName, difficultyID)
        if Utils.IsUsableString(name) then
            return name
        end
    end

    if type(GetDifficultyInfo) == "function" then
        local name = Utils.Call(GetDifficultyInfo, difficultyID)
        if Utils.IsUsableString(name) then
            return name
        end
    end
end

function Utils.IsHeroicDungeonTier(activityTierID)
    if not Utils.IsUsableNumber(activityTierID) then
        return false
    end

    if not (C_WeeklyRewards and type(C_WeeklyRewards.GetDifficultyIDForActivityTier) == "function") then
        return false
    end

    local difficultyID = Utils.Call(C_WeeklyRewards.GetDifficultyIDForActivityTier, activityTierID)
    if not Utils.IsUsableNumber(difficultyID) then
        return false
    end

    local heroicID = DifficultyUtil and DifficultyUtil.ID and DifficultyUtil.ID.DungeonHeroic
    return heroicID ~= nil and difficultyID == heroicID
end

function Utils.IsAddonLoaded(name)
    if C_AddOns and type(C_AddOns.IsAddOnLoaded) == "function" then
        return C_AddOns.IsAddOnLoaded(name)
    end
    if type(IsAddOnLoaded) == "function" then
        return IsAddOnLoaded(name)
    end
    return false
end

function Utils.LoadAddon(name)
    if Utils.IsAddonLoaded(name) then
        return
    end
    if C_AddOns and type(C_AddOns.LoadAddOn) == "function" then
        C_AddOns.LoadAddOn(name)
    elseif type(LoadAddOn) == "function" then
        LoadAddOn(name)
    end
end

function Utils.Print(message)
    local prefix = "|cff33ddff" .. ADDON_NAME .. "|r"
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message))
end

function Utils.CurrentSpecID()
    local specIndex = type(GetSpecialization) == "function" and GetSpecialization() or nil
    if not specIndex or type(GetSpecializationInfo) ~= "function" then
        return nil
    end
    return GetSpecializationInfo(specIndex)
end

-- The spec whose gear should be shown: Blizzard's Loot Specialization setting when the
-- player has one chosen, otherwise the active specialization (Loot Specialization returns
-- 0 for "Current Specialization").
function Utils.LootSpecID()
    local lootSpec = type(GetLootSpecialization) == "function" and GetLootSpecialization() or nil
    if Utils.IsUsableNumber(lootSpec) and lootSpec ~= 0 then
        return lootSpec
    end
    return Utils.CurrentSpecID()
end

-- Whether the player has an explicit Loot Specialization chosen (as opposed to "Current Specialization").
function Utils.HasExplicitLootSpec()
    local lootSpec = type(GetLootSpecialization) == "function" and GetLootSpecialization() or nil
    return Utils.IsUsableNumber(lootSpec) and lootSpec ~= 0
end

function Utils.LootSpecName(specID)
    if not Utils.IsUsableNumber(specID) or type(GetSpecializationInfoByID) ~= "function" then
        return nil
    end
    local _, name = Utils.Call(GetSpecializationInfoByID, specID)
    if Utils.IsUsableString(name) then
        return name
    end
end

-- Every specialization the player's own class can be, regardless of which is active.
function Utils.AvailableSpecs()
    local list = {}
    if type(GetNumSpecializations) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return list
    end
    local count = Utils.Call(GetNumSpecializations) or 0
    for index = 1, count do
        local id, name, _, icon = Utils.Call(GetSpecializationInfo, index)
        if Utils.IsUsableNumber(id) and Utils.IsUsableString(name) then
            list[#list + 1] = { id = id, name = name, icon = icon }
        end
    end
    return list
end

-- specID = nil/0 restores "Current Specialization".
function Utils.SetLootSpec(specID)
    if type(SetLootSpecialization) ~= "function" then
        return
    end
    Utils.Call(SetLootSpecialization, specID or 0)
end

function Utils.LootSpecLabel()
    local specID = Utils.LootSpecID()
    local name = Utils.LootSpecName(specID) or BGV.L["Unknown"]
    if Utils.HasExplicitLootSpec() then
        return name
    end
    return string.format(BGV.L["%s (current)"], name)
end

-- Fallback for clients without MenuUtil: steps to the next class specialization.
function Utils.CycleLootSpec()
    local specs = Utils.AvailableSpecs()
    if #specs == 0 then
        return
    end
    local current = Utils.LootSpecID()
    local nextIndex = 1
    for index, spec in ipairs(specs) do
        if spec.id == current then
            nextIndex = index % #specs + 1
            break
        end
    end
    Utils.SetLootSpec(specs[nextIndex].id)
end

function Utils.PlayerClassID()
    if type(UnitClass) ~= "function" then
        return nil
    end
    local _, _, classID = UnitClass("player")
    return Utils.IsUsableNumber(classID) and classID or nil
end

-- Every playable class: { id, name, file } in the game's class order.
function Utils.Classes()
    local list = {}
    if type(GetNumClasses) ~= "function" or type(GetClassInfo) ~= "function" then
        return list
    end
    for index = 1, Utils.Call(GetNumClasses) or 0 do
        local name, file, id = Utils.Call(GetClassInfo, index)
        if Utils.IsUsableNumber(id) and Utils.IsUsableString(name) then
            list[#list + 1] = { id = id, name = name, file = file }
        end
    end
    return list
end

-- The specializations of any class: { id, name }.
function Utils.ClassSpecs(classID)
    local list = {}
    -- Class 0 isn't a class: the game answers it with the hunter pet specs (Ferocity, ...).
    if not Utils.IsUsableNumber(classID) or classID <= 0 or type(GetSpecializationInfoForClassID) ~= "function" then
        return list
    end
    local count
    if C_SpecializationInfo and type(C_SpecializationInfo.GetNumSpecializationsForClassID) == "function" then
        count = Utils.Call(C_SpecializationInfo.GetNumSpecializationsForClassID, classID)
    elseif type(GetNumSpecializationsForClassID) == "function" then
        count = Utils.Call(GetNumSpecializationsForClassID, classID)
    end
    for index = 1, Utils.IsUsableNumber(count) and count or 5 do
        local id, name = Utils.Call(GetSpecializationInfoForClassID, classID, index)
        if Utils.IsUsableNumber(id) and Utils.IsUsableString(name) then
            list[#list + 1] = { id = id, name = name }
        end
    end
    return list
end

-- `text` in the class's color (for class names in menus and buttons).
function Utils.ClassColorText(classFile, text)
    local colors = RAID_CLASS_COLORS and type(classFile) == "string" and RAID_CLASS_COLORS[classFile]
    if colors and type(colors.colorStr) == "string" then
        return "|c" .. colors.colorStr .. text .. "|r"
    end
    return text
end

function Utils.LootSpecButtonEnabled()
    return not BetterGreatVaultDB or BetterGreatVaultDB.showLootSpecButton ~= false
end

-- Best-in-Slot tiers (Bis.lua) color the reels' items and fill the loot table's Tier column.
function Utils.ShowBisTiers()
    return not BetterGreatVaultDB or BetterGreatVaultDB.showBisTiers ~= false
end

-- The Loot Spec button used by both the Great Vault and the loot table; callers only position it.
-- `flat`: the addon's own flat style (the loot table) instead of Blizzard's red button.
function Utils.CreateLootSpecButton(parent, flat)
    local button
    if flat then
        button = Utils.CreateFlatButton(parent, 200, 22)
    else
        button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        button:SetSize(170, 20)
    end
    button:SetScript("OnClick", function(self)
        if not Utils.OpenLootSpecMenu(self) then
            Utils.CycleLootSpec()
        end
    end)
    return button
end

function Utils.RefreshLootSpecButton(button)
    if not button then
        return
    end
    if not Utils.LootSpecButtonEnabled() then
        button:Hide()
        return
    end
    button:SetText(string.format(BGV.L["Loot Spec: %s"], Utils.LootSpecLabel()))
    -- Wide enough for its label in any language.
    local label = button.GetFontString and button:GetFontString()
    if label and label.GetStringWidth then
        button:SetWidth(math.max(200, math.ceil((label:GetStringWidth() or 0) + 24)))
    end
    button:Show()
end

-- Returns true if a dropdown menu was opened at `anchor`, false if the client has no MenuUtil
-- and the caller should fall back to something like Utils.CycleLootSpec().
function Utils.OpenLootSpecMenu(anchor)
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        return false
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateRadio(BGV.L["Current Specialization"], function()
            return not Utils.HasExplicitLootSpec()
        end, function()
            Utils.SetLootSpec(0)
        end)
        for _, spec in ipairs(Utils.AvailableSpecs()) do
            root:CreateRadio(spec.name, function()
                return Utils.HasExplicitLootSpec() and Utils.LootSpecID() == spec.id
            end, function()
                Utils.SetLootSpec(spec.id)
            end)
        end
    end)
    return true
end

-- A flat-colored texture, used throughout the addon's custom frames (settings panel, loot table).
function Utils.Pixel(parent, layer, r, g, b, a)
    local texture = parent:CreateTexture(nil, layer or "BACKGROUND")
    texture:SetTexture("Interface\\Buttons\\WHITE8X8")
    texture:SetVertexColor(r, g, b, a or 1)
    return texture
end

-- Accent colors per specialization, used when the accent follows the spec (settings). Each
-- class's specs are clearly apart; the hex is the color as picked.
local SPEC_ACCENT = {
    -- Death Knight
    [250] = { 0.83, 0.16, 0.25 }, -- Blood #D42A3F
    [251] = { 0.50, 0.78, 1.00 }, -- Frost #7FC8FF
    [252] = { 0.49, 0.85, 0.23 }, -- Unholy #7DD83A
    -- Demon Hunter
    [577] = { 0.25, 0.88, 0.42 }, -- Havoc #3FE06B
    [581] = { 0.69, 0.27, 0.88 }, -- Vengeance #B044E0
    [1480] = { 0.36, 0.42, 1.00 }, -- Devourer #5C6BFF
    -- Druid
    [102] = { 0.48, 0.61, 1.00 }, -- Balance #7A9CFF
    [103] = { 1.00, 0.49, 0.04 }, -- Feral #FF7C0A
    [104] = { 0.75, 0.54, 0.32 }, -- Guardian #C08A52
    [105] = { 0.35, 0.82, 0.42 }, -- Restoration #58D26A
    -- Evoker
    [1467] = { 0.94, 0.31, 0.24 }, -- Devastation #F0503C
    [1468] = { 0.18, 0.83, 0.63 }, -- Preservation #2FD3A0
    [1473] = { 0.85, 0.65, 0.36 }, -- Augmentation #D9A55B
    -- Hunter
    [253] = { 0.67, 0.83, 0.45 }, -- Beast Mastery #AAD372
    [254] = { 0.43, 0.62, 0.84 }, -- Marksmanship #6E9FD6
    [255] = { 0.91, 0.54, 0.18 }, -- Survival #E8892E
    -- Mage
    [62] = { 0.71, 0.49, 1.00 }, -- Arcane #B47CFF
    [63] = { 1.00, 0.42, 0.12 }, -- Fire #FF6A1F
    [64] = { 0.39, 0.89, 0.96 }, -- Frost #63E3F5
    -- Monk
    [268] = { 0.89, 0.64, 0.23 }, -- Brewmaster #E3A43A
    [269] = { 0.18, 0.90, 0.61 }, -- Windwalker #2EE69B
    [270] = { 0.55, 0.81, 0.94 }, -- Mistweaver #8CCFF0
    -- Paladin
    [65] = { 1.00, 0.85, 0.35 }, -- Holy #FFD95A
    [66] = { 0.37, 0.55, 1.00 }, -- Protection #5E8CFF
    [70] = { 0.96, 0.55, 0.73 }, -- Retribution #F48CBA
    -- Priest
    [256] = { 0.66, 0.71, 1.00 }, -- Discipline #A8B6FF
    [257] = { 1.00, 0.95, 0.66 }, -- Holy #FFF1A8
    [258] = { 0.55, 0.32, 0.90 }, -- Shadow #8B52E6
    -- Rogue
    [259] = { 0.61, 0.84, 0.23 }, -- Assassination #9CD63A
    [260] = { 0.95, 0.80, 0.29 }, -- Outlaw #F2CC4A
    [261] = { 0.49, 0.42, 0.85 }, -- Subtlety #7D6BD9
    -- Shaman
    [262] = { 0.24, 0.55, 1.00 }, -- Elemental #3D8BFF
    [263] = { 0.91, 0.52, 0.25 }, -- Enhancement #E88540
    [264] = { 0.18, 0.77, 0.71 }, -- Restoration #2EC4B6
    -- Warlock
    [265] = { 0.64, 0.36, 0.94 }, -- Affliction #A45CF0
    [266] = { 0.43, 0.83, 0.29 }, -- Demonology #6ED44A
    [267] = { 1.00, 0.35, 0.16 }, -- Destruction #FF5A2A
    -- Warrior
    [71] = { 0.60, 0.65, 0.71 }, -- Arms #9AA6B4
    [72] = { 0.72, 0.28, 0.16 }, -- Fury #B8472A
    [73] = { 0.31, 0.48, 0.88 }, -- Protection #4F7BE0
}

-- The addon's accent color as { r, g, b }: the current spec's color, or the custom color chosen
-- in the settings, or the default gold.
function Utils.AccentColor()
    if not BetterGreatVaultDB or BetterGreatVaultDB.useSpecAccent ~= false then
        local specID = Utils.CurrentSpecID()
        return specID and SPEC_ACCENT[specID] or { 0.85, 0.65, 0.2 }
    end
    local saved = BetterGreatVaultDB.accentColor
    if type(saved) == "table" then
        local r = saved.r or saved[1]
        local g = saved.g or saved[2]
        local b = saved.b or saved[3]
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { r, g, b }
        end
    end
    return { 0.85, 0.65, 0.2 }
end

-- A 1px border around `target` (default: `parent`), drawn on `parent`, like the settings
-- panel's boxes.
function Utils.Border(parent, r, g, b, a, target)
    target = target or parent
    local edges = {}
    local function Edge(from, to, horizontal)
        local line = Utils.Pixel(parent, "BORDER", r, g, b, a)
        line:SetPoint(from, target, from, 0, 0)
        line:SetPoint(to, target, to, 0, 0)
        if horizontal then
            line:SetHeight(1)
        else
            line:SetWidth(1)
        end
        edges[#edges + 1] = line
    end
    Edge("TOPLEFT", "TOPRIGHT", true)
    Edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
    Edge("TOPLEFT", "BOTTOMLEFT", false)
    Edge("TOPRIGHT", "BOTTOMRIGHT", false)
    return edges
end

-- The addon's fonts: Blizzard's, at their size plus the text size offset chosen in the settings
-- (-5 to +5). The addon's text uses these (Utils.FontString), so a new offset resizes all of it.
local FONT_TEMPLATES = {
    Highlight = { template = "GameFontHighlight" },
    Normal = { template = "GameFontNormal" },
    HighlightSmall = { template = "GameFontHighlightSmall" },
    NormalSmall = { template = "GameFontNormalSmall" },
    NormalLarge = { template = "GameFontNormalLarge" },
    Disable = { template = "GameFontDisable" },
    -- The Great Vault slots' text: small and outlined.
    Vault = { template = "GameFontHighlightSmall", flags = "OUTLINE" },
}
-- Like Blizzard's, each is a family with one font per alphabet, so every language's text shows,
-- also when the language picked in the settings isn't the game's.
local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local fonts, fontMembers = {}, {}

function Utils.FontOffset()
    local value = BetterGreatVaultDB and BetterGreatVaultDB.fontSize
    if type(value) ~= "number" then
        return 0
    end
    return math.max(-5, math.min(5, math.floor(value + 0.5)))
end

-- The text size as a ratio to Blizzard's, for a text of `base` size (default 10).
function Utils.FontScale(base)
    base = base or 10
    return (base + Utils.FontOffset()) / base
end

local function TemplateMembers(template, flags)
    local members = {}
    for _, alphabet in ipairs(ALPHABETS) do
        local source = template
        if type(template.GetFontObjectForAlphabet) == "function" then
            source = template:GetFontObjectForAlphabet(alphabet) or template
        end
        local file, height, ownFlags
        if type(source.GetFont) == "function" then
            file, height, ownFlags = source:GetFont()
        end
        if file and height then
            members[#members + 1] = {
                alphabet = alphabet, file = file, height = height, flags = flags or ownFlags or "", source = source,
            }
        end
    end
    return members
end

local function CreateAddonFont(key, spec)
    local template = _G[spec.template]
    if not template then
        return nil
    end
    local name = "BetterGreatVaultFont" .. key
    local members = TemplateMembers(template, spec.flags)
    if type(CreateFontFamily) == "function" and #members > 0 then
        local definition = {}
        for index, member in ipairs(members) do
            definition[index] = { alphabet = member.alphabet, file = member.file, height = member.height, flags = member.flags }
        end
        local ok, font = pcall(CreateFontFamily, name, definition)
        if ok and font then
            -- A family's definition has no color or shadow: each member takes Blizzard's.
            for _, member in ipairs(members) do
                local target = font:GetFontObjectForAlphabet(member.alphabet)
                if target then
                    target:SetTextColor(member.source:GetTextColor())
                    target:SetShadowColor(member.source:GetShadowColor())
                    target:SetShadowOffset(member.source:GetShadowOffset())
                end
            end
            fontMembers[key] = members
            return font
        end
    end
    -- Without font families: one font, in the game's own alphabet.
    if type(CreateFont) ~= "function" then
        return nil
    end
    local font = CreateFont(name)
    font:CopyFontObject(template)
    local file, height, flags = font:GetFont()
    fontMembers[key] = { { file = file, height = height, flags = spec.flags or flags or "" } }
    return font
end

-- The addon's font object for `key`: Highlight, Normal, HighlightSmall, NormalSmall,
-- NormalLarge, Disable or Vault.
function Utils.Font(key)
    return fonts[key] or _G["GameFont" .. key] or GameFontHighlight
end

-- A font string in the addon's font `key`.
function Utils.FontString(parent, layer, key)
    local text = parent:CreateFontString(nil, layer or "OVERLAY")
    text:SetFontObject(Utils.Font(key))
    return text
end

function Utils.ApplyFontSize()
    local offset = Utils.FontOffset()
    for key, spec in pairs(FONT_TEMPLATES) do
        local font = fonts[key]
        if not font then
            font = CreateAddonFont(key, spec)
            fonts[key] = font
        end
        for _, member in ipairs(font and fontMembers[key] or {}) do
            local target = font
            if member.alphabet and type(font.GetFontObjectForAlphabet) == "function" then
                target = font:GetFontObjectForAlphabet(member.alphabet) or font
            end
            target:SetFont(member.file, math.max(4, member.height + offset), member.flags)
        end
    end
end

Utils.ApplyFontSize()

-- A flat button in the addon's own style (dark fill, 1px border, soft hover glow), with a font
-- string so :SetText works as on Blizzard's buttons.
function Utils.CreateFlatButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, height or 22)
    button.back = Utils.Pixel(button, "BACKGROUND", 0.12, 0.12, 0.135, 1)
    button.back:SetAllPoints()
    Utils.Border(button, 0.3, 0.3, 0.33, 1)
    local glow = Utils.Pixel(button, "HIGHLIGHT", 1, 1, 1, 0.07)
    glow:SetAllPoints()
    local text = Utils.FontString(button, "OVERLAY", "HighlightSmall")
    text:SetPoint("LEFT", button, "LEFT", 8, 0)
    text:SetPoint("RIGHT", button, "RIGHT", -8, 0)
    text:SetWordWrap(false)
    button:SetFontString(text)
    button:SetPushedTextOffset(0, -1)
    return button
end

-- Upper case for the small headings, in any of the addon's languages: string.upper only knows
-- English letters, so accented Latin (é, ü, ñ) and Cyrillic (ж, і, ї, є, ґ) letters are mapped
-- here. Other scripts have no case.
function Utils.Upper(text)
    -- By byte range, not string.upper: that follows the process locale, which can touch the
    -- bytes of UTF-8 letters.
    text = text:gsub("[a-z]", function(letter)
        return string.char(letter:byte() - 32)
    end)
    text = text:gsub("\195([\160-\190])", function(byte)
        if byte == "\183" then
            return nil
        end
        return "\195" .. string.char(byte:byte() - 32)
    end)
    text = text:gsub("\208([\176-\191])", function(byte)
        return "\208" .. string.char(byte:byte() - 32)
    end)
    text = text:gsub("\209([\128-\143])", function(byte)
        return "\208" .. string.char(byte:byte() + 32)
    end)
    text = text:gsub("\209([\144-\159])", function(byte)
        return "\208" .. string.char(byte:byte() - 16)
    end)
    text = text:gsub("\210\145", "\210\144")
    return text
end

function Utils.Trim(value)
    if type(value) ~= "string" then
        return ""
    end
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end
