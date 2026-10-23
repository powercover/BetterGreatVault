-- Translations and fonts: every locale file with a fresh Utils, the game's fonts mocked as
-- per-alphabet families.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("I18N FAIL: " .. message) end end

local ALPHABETS = { "roman", "russian", "korean", "simplifiedchinese", "traditionalchinese" }
local function FontObject(file, height, flags)
  local font = { file = file, height = height, flags = flags, color = { 1, 1, 1, 1 }, shadow = { 0, 0, 0, 1 }, offset = { 1, -1 } }
  function font:GetFont() return self.file, self.height, self.flags end
  function font:SetFont(f, h, fl) self.file, self.height, self.flags = f, h, fl end
  function font:GetTextColor() return unpack(self.color) end
  function font:SetTextColor(r, g, b, a) self.color = { r, g, b, a or 1 } end
  function font:GetShadowColor() return unpack(self.shadow) end
  function font:SetShadowColor(r, g, b, a) self.shadow = { r, g, b, a or 1 } end
  function font:GetShadowOffset() return unpack(self.offset) end
  function font:SetShadowOffset(x, y) self.offset = { x, y } end
  return font
end
local FILES = { roman = "FRIZQT__.TTF", russian = "FRIZQT___CYR.TTF", korean = "2002.TTF",
  simplifiedchinese = "ARKai_T.ttf", traditionalchinese = "blei00d.TTF" }
local function Family(height, color)
  local family = { members = {} }
  for _, alphabet in ipairs(ALPHABETS) do
    local cjk = alphabet == "simplifiedchinese" or alphabet == "traditionalchinese"
    family.members[alphabet] = FontObject(FILES[alphabet], height + (cjk and 3 or 0), "")
    if color then family.members[alphabet]:SetTextColor(unpack(color)) end
  end
  function family:GetFontObjectForAlphabet(alphabet) return self.members[alphabet] end
  function family:GetFont() return self.members.roman:GetFont() end
  return family
end
GameFontHighlight, GameFontNormal = Family(12), Family(12, { 1, 0.82, 0, 1 })
GameFontHighlightSmall, GameFontNormalSmall = Family(10), Family(10, { 1, 0.82, 0, 1 })
GameFontNormalLarge, GameFontDisable = Family(16, { 1, 0.82, 0, 1 }), Family(12, { 0.5, 0.5, 0.5, 1 })
local created = {}
function CreateFontFamily(name, members)
  local family = { members = {}, name = name }
  for _, member in ipairs(members) do
    family.members[member.alphabet] = FontObject(member.file, member.height, member.flags)
  end
  function family:GetFontObjectForAlphabet(alphabet) return self.members[alphabet] end
  created[name] = family
  return family
end
local gameLocale = "enUS"
function GetLocale() return gameLocale end
RAIDS, DUNGEONS = "Raids", "Dungeons"
BetterGreatVaultDB = {}

local BGV = {}
local order = { "Locales/Locales.lua", "Locales/deDE.lua", "Locales/esES.lua", "Locales/esMX.lua", "Locales/frFR.lua",
  "Locales/itIT.lua", "Locales/koKR.lua", "Locales/ptBR.lua", "Locales/ruRU.lua", "Locales/ukUA.lua", "Locales/zhCN.lua",
  "Locales/zhTW.lua", "Utils.lua" }
for _, path in ipairs(order) do assert(loadfile(path))("BetterGreatVault", BGV) end
local L, Locale, Utils = BGV.L, BGV.Locale, BGV.Utils

-- fonts: families with every alphabet, sized with the text size
local highlight = Utils.Font("Highlight")
check(created.BetterGreatVaultFontHighlight == highlight, "Highlight is a font family")
for _, alphabet in ipairs(ALPHABETS) do
  check(highlight:GetFontObjectForAlphabet(alphabet) ~= nil, "Highlight has the " .. alphabet .. " alphabet")
end
check(highlight:GetFontObjectForAlphabet("russian").file == "FRIZQT___CYR.TTF", "Cyrillic keeps its own font")
check(highlight:GetFontObjectForAlphabet("simplifiedchinese").height == 15, "each alphabet keeps its own height")
check(Utils.Font("Vault"):GetFontObjectForAlphabet("roman").flags == "OUTLINE", "the vault font is outlined")
check(Utils.Font("Normal"):GetFontObjectForAlphabet("roman").color[2] == 0.82, "members take Blizzard's colors")
BetterGreatVaultDB.fontSize = 3
Utils.ApplyFontSize()
check(highlight:GetFontObjectForAlphabet("roman").height == 15 and highlight:GetFontObjectForAlphabet("russian").height == 15
  and highlight:GetFontObjectForAlphabet("traditionalchinese").height == 18, "text size +3 for every alphabet")
BetterGreatVaultDB.fontSize = -5
Utils.ApplyFontSize()
check(Utils.Font("HighlightSmall"):GetFontObjectForAlphabet("roman").height == 5, "text size -5")
BetterGreatVaultDB.fontSize = 0
Utils.ApplyFontSize()
check(highlight:GetFontObjectForAlphabet("roman").height == 12, "back to the game's size")
local text = Utils.FontString({ CreateFontString = function() return { SetFontObject = function(self, f) self.font = f end } end }, "OVERLAY", "Highlight")
check(text.font == highlight, "font strings get the family as their font object")

-- languages
Locale.Apply()
check(L["Settings"] == "Settings" and not Locale.Foreign(), "English by default on an English game")
BetterGreatVaultDB.language = "ukUA"
Locale.Apply()
check(L["Settings"] == "Налаштування", "Ukrainian when picked: " .. L["Settings"])
check(Locale.Foreign(), "Ukrainian isn't the game's language")
check(Utils.GameText("RAIDS", "Raids") == "Рейди", "the game's words in the addon's language when it differs: " .. Utils.GameText("RAIDS", "Raids"))
check(Utils.DifficultyName(16) == "Міфічний" and Utils.DifficultyName(17) == "Пошук рейду", "difficulty names in the addon's language")
check(L["Not a key"] == "Not a key", "text without a translation stays English")
BetterGreatVaultDB.language = "auto"
gameLocale = "deDE"
Locale.Apply()
check(L["Settings"] == "Einstellungen" and not Locale.Foreign(), "the game's language when set to auto")
RAIDS = "Schlachtzüge"
check(Utils.GameText("RAIDS", "Raids") == "Schlachtzüge", "the game's own word when the languages match")
gameLocale = "esMX"
Locale.Apply()
check(L["Great Vault"] == "Gran Bóveda", "Latin American Spanish: " .. L["Great Vault"])
gameLocale = "enGB"
Locale.Apply()
check(L["Settings"] == "Settings", "British English is English")
check(Locale.Name("ukUA") == "Українська (Ukrainian)", "language names")

-- upper case in any script
check(Utils.Upper("цей тиждень") == "ЦЕЙ ТИЖДЕНЬ", "Ukrainian upper case: " .. Utils.Upper("цей тиждень"))
check(Utils.Upper("ґанок їжак єнот і ё") == "ҐАНОК ЇЖАК ЄНОТ І Ё", "Ukrainian letters: " .. Utils.Upper("ґанок їжак єнот і ё"))
check(Utils.Upper("sekundärwerte über édition ñ") == "SEKUNDÄRWERTE ÜBER ÉDITION Ñ", "accented Latin: " .. Utils.Upper("sekundärwerte über édition ñ"))
check(Utils.Upper("2÷3 ß") == "2÷3 ß", "÷ and ß stay")
check(Utils.Upper("本周") == "本周", "no case in Chinese")

-- every translation formats with the addon's arguments
local samples = { d = 7, s = "x", i = 7, f = 1.5, x = 255 }
local codes = {}
for _, language in ipairs(Locale.LANGUAGES) do codes[#codes + 1] = language.code end
codes[#codes + 1] = "esMX"
local formatted = 0
for _, code in ipairs(codes) do
  if code ~= "enUS" then
    BetterGreatVaultDB.language = code
    Locale.Apply()
    for _, key in ipairs({ "%d of %d unlocked", "Weekly reset in %dd %dh", "Category: %s | Slot: %d | Progress: %d | Required: %d | Reward ilvl: %s",
        "Vault reward: %d item level, %d from the raid's last two bosses", "Items with both %s and %s", "%s %d (%d from the last two bosses)",
        "Reward: %s %d/%d (%d ilvl)", "Delve tier %d x%d", "Slot %s", "Tier %d", "Mythic+ %d", "Version %s  •  by %s" }) do
      local args = {}
      for kind in key:gmatch("%%(%a)") do args[#args + 1] = samples[kind] end
      local ok, result = pcall(string.format, L[key], unpack(args))
      check(ok and result ~= L[key], code .. " formats " .. key .. ": " .. tostring(result))
      formatted = formatted + 1
    end
  end
end

-- loading on a German client: the game's language speaks as soon as its file has loaded, before the
-- saved settings are known (ADDON_LOADED), so text the other files make as they load is German too;
-- and Latin American Spanish is in the settings' list
do
  local savedDB, savedLocale = BetterGreatVaultDB, gameLocale
  BetterGreatVaultDB, gameLocale = nil, "deDE"
  local early = {}
  for _, path in ipairs({ "Locales/Locales.lua", "Locales/deDE.lua", "Locales/esES.lua" }) do
    assert(loadfile(path))("BetterGreatVault", early)
  end
  check(early.L["World"] == "Welt" and early.L["Delves"] == "Tiefen", "German from its file on: " .. tostring(early.L["World"]))
  local listed = false
  for _, language in ipairs(early.Locale.LANGUAGES) do listed = listed or language.code == "esMX" end
  check(listed, "Latin American Spanish is in the list")
  BetterGreatVaultDB, gameLocale = savedDB, savedLocale
end

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  check(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end
print("i18n formatted", formatted, "strings")
print(fails == 0 and "i18n checks passed" or (fails .. " i18n checks failed"))
