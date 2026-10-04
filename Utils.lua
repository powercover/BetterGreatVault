local _, BGV = ...

BGV.Utils = {}

local Utils = BGV.Utils

local ADDON_NAME = "Better Great Vault"

function Utils.IsSecret(value)
    if type(issecretvalue) ~= "function" then
        return false
    end

    -- a check that fails counts as secret: the value isn't safe to compare or do sums with
    local ok, secret = pcall(issecretvalue, value)
    return not ok or secret == true
end

function Utils.IsUsableNumber(value)
    return type(value) == "number" and not Utils.IsSecret(value)
end

-- Checked for a secret before it's compared: comparing a secret string is itself an error.
function Utils.IsUsableString(value)
    return type(value) == "string" and not Utils.IsSecret(value) and value ~= ""
end

local function Answered(ok, first, ...)
    if not ok or Utils.IsSecret(first) then
        return
    end
    return first, ...
end

-- Calls a Blizzard function that may be missing, fail, or answer with a secret value: nothing
-- comes back then. Every result comes back otherwise, nils in between included.
function Utils.Call(func, ...)
    if type(func) ~= "function" then
        return
    end
    return Answered(pcall(func, ...))
end

-- --- errors ------------------------------------------------------------------------------------

-- Errors the addon caught (Utils.Protect): the last few, each with how often it happened.
-- /bgv debug lists them.
BGV.errors = {}
local MAX_ERRORS = 10

function Utils.NoteError(label, err)
    -- an error carrying a secret value can't be compared with the ones noted before
    local message = Utils.IsSecret(err) and "(secret value)" or tostring(err)
    if Utils.IsSecret(message) then
        message = "(secret value)"
    end
    for _, known in ipairs(BGV.errors) do
        if known.message == message then
            known.count = known.count + 1
            return
        end
    end
    if #BGV.errors >= MAX_ERRORS then
        table.remove(BGV.errors, 1)
    end
    BGV.errors[#BGV.errors + 1] = { label = label, message = message, count = 1 }
    if BetterGreatVaultDB and BetterGreatVaultDB.debug and type(Utils.Print) == "function" then
        Utils.Print(label .. ": " .. message)
    end
end

local function Settled(label, ok, ...)
    if ok then
        return ...
    end
    Utils.NoteError(label, (...))
end

-- `fn` wrapped so an error in it is caught and noted (Utils.NoteError) instead of reaching the
-- game's error frame, or the Blizzard code that called it when `fn` hooks it: an addon's mistake
-- must never break the Great Vault, a tooltip or another addon's data bar.
function Utils.Protect(label, fn)
    return function(...)
        return Settled(label, pcall(fn, ...))
    end
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

-- An item's instant info (no cache needed): C_Item's, or the old global the game had before it.
function Utils.ItemInfoInstant(itemID)
    local getInfo = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
    if not Utils.IsUsableNumber(itemID) or type(getInfo) ~= "function" then
        return
    end
    return Utils.Call(getInfo, itemID)
end

function Utils.Print(message)
    local prefix = "|cff33ddff" .. ADDON_NAME .. "|r"
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. ": " .. tostring(message))
end

-- The player's specializations come from C_SpecializationInfo: in 12.x the bare GetSpecialization
-- and GetSpecializationInfo are deprecation fallbacks only (the loadDeprecationFallbacks setting)
-- and will go. The globals stay as a fallback.
local function SpecializationInfo(index)
    local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo or GetSpecializationInfo
    if type(get) == "function" then
        return Utils.Call(get, index)
    end
end

-- The active specialization's ID (nil without one).
function Utils.CurrentSpecID()
    local get = C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    local specIndex = type(get) == "function" and Utils.Call(get) or nil
    if not Utils.IsUsableNumber(specIndex) then
        return nil
    end
    local specID = SpecializationInfo(specIndex)
    if Utils.IsUsableNumber(specID) and specID ~= 0 then
        return specID
    end
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
    if type(GetNumSpecializations) ~= "function" then
        return list
    end
    local count = Utils.Call(GetNumSpecializations) or 0
    for index = 1, Utils.IsUsableNumber(count) and count or 0 do
        local id, name, _, icon = SpecializationInfo(index)
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

-- Slot animations off (settings): the vault's slots show still gates, and rewards stay Blizzard's.
function Utils.AnimationsOff()
    return BetterGreatVaultDB ~= nil and BetterGreatVaultDB.disableAnimations == true
end

-- The vault shows this week's progress, not rewards rolled (to choose at the vault, or waiting
-- away from it): the only time the addon lays out the slots itself (Rewards.ShowingWeeklyProgress).
function Utils.ProgressWeek()
    local rewards = BGV.Rewards
    return not (rewards and type(rewards.ShowingWeeklyProgress) == "function") or rewards.ShowingWeeklyProgress() == true
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

-- A flat button in the addon's own style (dark fill, 1px border, soft hover glow). Its label is
-- a plain font string rather than the button's own text (SetFontString): in the game, button
-- text showed Cyrillic as boxes while the plain font strings around it (headings, notes) showed
-- it fine. :SetText, :GetText and :GetFontString work on the label as on Blizzard's buttons.
function Utils.CreateFlatButton(parent, width, height)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width or 120, height or 22)
    button.back = Utils.Pixel(button, "BACKGROUND", 0.12, 0.12, 0.135, 1)
    button.back:SetAllPoints()
    Utils.Border(button, 0.3, 0.3, 0.33, 1)
    local glow = Utils.Pixel(button, "HIGHLIGHT", 1, 1, 1, 0.07)
    glow:SetAllPoints()
    local text = Utils.FontString(button, "OVERLAY", "HighlightSmall")
    text:SetWordWrap(false)
    -- Pressed, the label dips a pixel (what SetPushedTextOffset did).
    local function Place(dip)
        text:SetPoint("LEFT", button, "LEFT", 8, dip)
        text:SetPoint("RIGHT", button, "RIGHT", -8, dip)
    end
    Place(0)
    button:HookScript("OnMouseDown", function(self)
        if self:IsEnabled() then
            Place(-1)
        end
    end)
    button:HookScript("OnMouseUp", function()
        Place(0)
    end)
    function button:SetText(value)
        text:SetText(value)
    end
    function button:GetText()
        return text:GetText()
    end
    function button:GetFontString()
        return text
    end
    return button
end

-- The spinning vault emblem (the minimap popup's and About's): the icon's layers, with the
-- handle turning slowly, then winding up and taking off in an old-cartoon burst of speed (a spin
-- blur, streaks behind the knobs, swoosh arcs, dust puffs, a rattle, squash and stretch), then
-- easing back to slow. One cycle is SPIN_PERIOD seconds; it animates only while shown.
local EMBLEM_MEDIA = "Interface\\AddOns\\BetterGreatVault\\Media\\"
local SPIN_SLOW, SPIN_BACK, SPIN_FAST = 0.9, -1.4, 28 -- radians a second, counter-clockwise
local SPIN_PERIOD = 6.2
local SPIN_START = 1.4 -- where a showing starts, so the burst comes a second later
-- The most the handle turns in one frame: under half its 90 degree symmetry, so a low frame
-- rate can't make it look like it's turning backwards.
local SPIN_MAX_STEP = 0.65
local PUFF_LIFE = 0.45
local PUFF_COUNT = 6

local function Smooth(x)
    x = math.max(0, math.min(1, x))
    return x * x * (3 - 2 * x)
end

-- The spin's speed `t` seconds into the cycle: slow; backing off a little (the wind-up); taking
-- off; flat out; then slowing down.
local function SpinSpeed(t)
    if t < 2.4 then
        return SPIN_SLOW
    elseif t < 2.75 then
        return SPIN_SLOW + (SPIN_BACK - SPIN_SLOW) * Smooth((t - 2.4) / 0.12)
    elseif t < 3.2 then
        return SPIN_BACK + (SPIN_FAST - SPIN_BACK) * Smooth((t - 2.75) / 0.45)
    elseif t < 4.4 then
        return SPIN_FAST
    end
    return SPIN_SLOW + (SPIN_FAST - SPIN_SLOW) * (1 - (t - 4.4) / (SPIN_PERIOD - 4.4)) ^ 3
end

-- The size the emblem springs toward: squashed on the wind-up, swollen at speed.
local function SpinScale(t)
    if t >= 2.4 and t < 2.75 then
        return 0.9
    elseif t >= 2.75 and t < 4.4 then
        return 1.06
    end
    return 1
end

function Utils.CreateEmblem(parent, size)
    local emblem = CreateFrame("Frame", nil, parent)
    emblem:SetSize(size, size)
    -- The layers ride on a body that rattles and squashes; the emblem itself stays put for anchors.
    local body = CreateFrame("Frame", nil, emblem)
    body:SetSize(size, size)
    body:SetPoint("CENTER", emblem, "CENTER", 0, 0)
    local function Layer(file, drawLayer, sublevel, scale)
        local texture = body:CreateTexture(nil, drawLayer, nil, sublevel)
        texture:SetTexture(EMBLEM_MEDIA .. file)
        texture:SetSize(size * (scale or 1), size * (scale or 1))
        texture:SetPoint("CENTER", body, "CENTER", 0, 0)
        return texture
    end
    Layer("MinimapBase", "ARTWORK", 0)
    local blur = Layer("EmblemBlur", "ARTWORK", 1)
    local wheel = Layer("MinimapWheel", "ARTWORK", 2)
    local trails = Layer("EmblemTrails", "ARTWORK", 3)
    Layer("MinimapGem", "OVERLAY", 0)
    -- The arcs' texture is 1.6 times the emblem, so they swoop around outside the rim.
    local arcs = Layer("EmblemArcs", "OVERLAY", 1, 1.6)
    local puffs = {}
    for index = 1, PUFF_COUNT do
        local texture = body:CreateTexture(nil, "OVERLAY", nil, 2)
        texture:SetTexture(EMBLEM_MEDIA .. "CasePuffs")
        texture:Hide()
        puffs[index] = { texture = texture }
    end

    local spin = { t = SPIN_START, angle = 0, speed = SPIN_SLOW, effect = 0, scale = 1, velocity = 0, spawn = 0, puffs = puffs }
    emblem.spin = spin

    -- A puff thrown off the rim, flung along the spin; it grows as it goes and fades out. Each
    -- is one of four cloud shapes, mirrored at random, tilted, turning a little, and stretched.
    local function Puff()
        for _, puff in ipairs(puffs) do
            if not puff.active then
                puff.active, puff.age, puff.angle = true, 0, math.random() * 2 * math.pi
                local shape = math.random(4)
                local left, right = (shape - 1) / 4, shape / 4
                if math.random() < 0.5 then
                    left, right = right, left
                end
                puff.texture:SetTexCoord(left, right, 0, 1)
                puff.tilt = (math.random() - 0.5) * 1.0
                puff.turn = (math.random() - 0.5) * 1.6
                puff.aspect = 0.85 + math.random() * 0.35
                puff.texture:Show()
                return
            end
        end
    end

    local function PlacePuff(puff)
        local life = puff.age / PUFF_LIFE
        local travel = size * 0.3 * (1 - (1 - life) ^ 2)
        local radial, tangent = size * 0.5 + travel * 0.75, travel * 0.66
        local cos, sin = math.cos(puff.angle), math.sin(puff.angle)
        local puffSize = size * (0.16 + 0.16 * life)
        puff.texture:SetSize(puffSize * puff.aspect, puffSize)
        puff.texture:SetRotation(puff.tilt + puff.turn * puff.age)
        puff.texture:SetPoint("CENTER", body, "CENTER", cos * radial - sin * tangent, sin * radial + cos * tangent)
        puff.texture:SetAlpha(0.95 * (1 - life * life))
    end

    -- Once a frame while shown: only what moves is touched (no tables made, so no garbage).
    local effects = { blur, trails, arcs }
    local pose = { shown = nil, scale = nil, rattled = true }
    local function Pose()
        local effect = spin.effect
        wheel:SetRotation(spin.angle)
        wheel:SetAlpha(1 - 0.6 * effect)
        local shown = effect > 0
        if pose.shown ~= shown then
            pose.shown = shown
            for index = 1, 3 do
                effects[index]:SetShown(shown)
            end
        end
        if shown then
            blur:SetRotation(spin.angle)
            blur:SetAlpha(0.9 * effect)
            trails:SetRotation(spin.angle)
            trails:SetAlpha(effect)
            arcs:SetRotation(spin.angle * 0.85)
            arcs:SetAlpha(effect)
        end
        local scale = math.max(0.5, spin.scale)
        if pose.scale ~= scale then
            pose.scale = scale
            body:SetScale(scale)
        end
        -- The rattle at full tilt, a pixel or so either way.
        local rattle = effect > 0.5 and effect * size / 30 * 0.7 or 0
        if rattle > 0 or pose.rattled then
            pose.rattled = rattle > 0
            body:SetPoint("CENTER", emblem, "CENTER", (math.random() * 2 - 1) * rattle, (math.random() * 2 - 1) * rattle)
        end
    end

    local function Animate(_, elapsed)
        elapsed = math.min(elapsed or 0, 0.05)
        local before = spin.t
        spin.t = (spin.t + elapsed) % SPIN_PERIOD
        spin.speed = SpinSpeed(spin.t)
        local step = math.max(-SPIN_MAX_STEP, math.min(SPIN_MAX_STEP, spin.speed * elapsed))
        spin.angle = (spin.angle + step) % (2 * math.pi)
        spin.effect = Smooth((spin.speed - 6) / (SPIN_FAST - 6))
        -- Squash and stretch: a spring toward the phase's size, so it overshoots a little.
        spin.velocity = spin.velocity + ((SpinScale(spin.t) - spin.scale) * 260 - spin.velocity * 16) * elapsed
        spin.scale = spin.scale + spin.velocity * elapsed
        -- Puffs: a burst at takeoff, then a steady few while flat out.
        if before < 2.75 and spin.t >= 2.75 then
            for _ = 1, 4 do
                Puff()
            end
        end
        spin.spawn = spin.spawn - elapsed
        if spin.effect > 0.7 and spin.spawn <= 0 then
            spin.spawn = 0.14
            Puff()
        end
        for _, puff in ipairs(puffs) do
            if puff.active then
                puff.age = puff.age + elapsed
                if puff.age >= PUFF_LIFE then
                    puff.active = false
                    puff.texture:Hide()
                else
                    PlacePuff(puff)
                end
            end
        end
        Pose()
    end

    -- Each showing starts over from the slow spin.
    emblem:SetScript("OnShow", function()
        spin.t, spin.speed, spin.effect, spin.scale, spin.velocity, spin.spawn = SPIN_START, SPIN_SLOW, 0, 1, 0, 0
        for _, puff in ipairs(puffs) do
            puff.active = false
            puff.texture:Hide()
        end
        Pose()
    end)
    -- It spins while shown, unless paused (the settings page pauses it while it's scrolled away).
    function emblem:SetAnimated(on)
        if self.bgvAnimated ~= on then
            self.bgvAnimated = on
            self:SetScript("OnUpdate", on and Animate or nil)
        end
    end
    emblem:SetAnimated(true)
    Pose()
    return emblem
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
