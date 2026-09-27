local _, BGV = ...

-- Translations. The addon's text is written in English and looked up through BGV.L: L["Settings"]
-- is the chosen language's text, or the English itself when there's no translation for it.
BGV.Locale = {}

local Locale = BGV.Locale
local translations = {}
local active = {}

BGV.L = setmetatable({}, {
    __index = function(_, text)
        return active[text] or text
    end,
})

-- The languages to choose from in the settings, by the game's locale codes. The game has no
-- Ukrainian client, so Ukrainian (ukUA) is only reached by choosing it.
Locale.LANGUAGES = {
    { code = "enUS", name = "English" },
    { code = "deDE", name = "Deutsch (German)" },
    { code = "esES", name = "Español (Spanish)" },
    { code = "frFR", name = "Français (French)" },
    { code = "itIT", name = "Italiano (Italian)" },
    { code = "ptBR", name = "Português (Portuguese)" },
    { code = "ruRU", name = "Русский (Russian)" },
    { code = "ukUA", name = "Українська (Ukrainian)" },
    { code = "koKR", name = "한국어 (Korean)" },
    { code = "zhCN", name = "简体中文 (Chinese, Simplified)" },
    { code = "zhTW", name = "繁體中文 (Chinese, Traditional)" },
}

-- Game locales that share another's translation.
local SAME_AS = { enGB = "enUS" }

function Locale.Register(code, strings)
    translations[code] = strings
end

-- The saved choice: "auto" (the game's language) or a locale code.
function Locale.Choice()
    local saved = BetterGreatVaultDB and BetterGreatVaultDB.language
    if type(saved) == "string" and saved ~= "" then
        return saved
    end
    return "auto"
end

-- The language the addon speaks now: the chosen one, or the game's.
function Locale.Current()
    local code = Locale.Choice()
    if code == "auto" then
        code = type(GetLocale) == "function" and GetLocale() or "enUS"
    end
    return SAME_AS[code] or code
end

-- Takes up the chosen language. Text already on screen keeps its language until the interface
-- is reloaded.
function Locale.Apply()
    active = translations[Locale.Current()] or {}
end

-- Whether the addon speaks another language than the game (one picked in the settings).
function Locale.Foreign()
    local game = type(GetLocale) == "function" and GetLocale() or "enUS"
    return Locale.Current() ~= (SAME_AS[game] or game)
end

-- A language's name, as the settings list it.
function Locale.Name(code)
    for _, language in ipairs(Locale.LANGUAGES) do
        if language.code == (SAME_AS[code] or code) then
            return language.name
        end
    end
    return code
end

-- Until the saved choice is known (ADDON_LOADED), the game's language.
Locale.Apply()
