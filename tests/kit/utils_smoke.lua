-- Utils.lua's guards and the spec helpers: a value is checked for a secret before it's compared, a
-- failing check counts as secret, an error carrying a secret is noted safely, and the spec helpers
-- read C_SpecializationInfo (12.x's bare GetSpecialization/GetSpecializationInfo are deprecation
-- fallbacks only).
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("UTILS FAIL: " .. message) end end

local SECRET = setmetatable({}, { __tostring = function() return "a secret" end })
local checked = 0
function issecretvalue(value)
  checked = checked + 1
  if value == "boom" then error("cannot check") end
  return value == SECRET
end
BetterGreatVaultDB = {}
function GetLocale() return "enUS" end
local BGV = {}
for _, path in ipairs({ "Locales/Locales.lua", "Utils.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end
local Utils = BGV.Utils

-- checked before compared
checked = 0
check(Utils.IsUsableString("") == false, "an empty string isn't usable")
check(checked == 1, "a string is checked for a secret before it's compared with \"\": " .. checked)
check(Utils.IsUsableString("Vengeance") == true, "a plain string is usable")
check(Utils.IsUsableString(SECRET) == false and Utils.IsUsableNumber(SECRET) == false, "a secret is neither")
-- a check that fails counts as secret
check(Utils.IsSecret("boom") == true, "a failing check counts as secret")
check(Utils.IsUsableString("boom") == false, "and isn't usable")

-- an error carrying a secret is noted without comparing it
Utils.NoteError("test", SECRET)
Utils.NoteError("test", SECRET)
local noted = BGV.errors[#BGV.errors]
check(noted and noted.message == "(secret value)" and noted.count == 2, "a secret error is noted safely: " .. tostring(noted and noted.message))
for i = #BGV.errors, 1, -1 do table.remove(BGV.errors, i) end

-- the spec helpers on C_SpecializationInfo alone (no deprecated globals)
GetSpecialization, GetSpecializationInfo = nil, nil
local SPECS = { { 577, "Havoc" }, { 581, "Vengeance" }, { 1480, "Devourer" } }
local active = 2
C_SpecializationInfo = {
  GetSpecialization = function() return active end,
  GetSpecializationInfo = function(index)
    local spec = SPECS[index]
    if spec then return spec[1], spec[2], "", 1000 + index end
    return 0
  end,
}
function GetNumSpecializations() return #SPECS end
check(Utils.CurrentSpecID() == 581, "the active spec from C_SpecializationInfo: " .. tostring(Utils.CurrentSpecID()))
check(select("#", Utils.CurrentSpecID()) == 1, "just the spec's ID")
local specs = Utils.AvailableSpecs()
check(#specs == 3 and specs[3].id == 1480 and specs[3].name == "Devourer", "every spec of the class from C_SpecializationInfo")
active = 5 -- a character without a specialization yet: the game answers 0
check(Utils.CurrentSpecID() == nil, "no specialization: none")
active = 1
function GetLootSpecialization() return 0 end
check(Utils.LootSpecID() == 577, "loot spec \"current\": the active spec")
-- and the deprecated globals still work where C_SpecializationInfo isn't there
C_SpecializationInfo = nil
function GetSpecialization() return 3 end
function GetSpecializationInfo(index) local spec = SPECS[index] return spec[1], spec[2] end
check(Utils.CurrentSpecID() == 1480, "the bare globals as a fallback")

for _, e in ipairs(BGV.errors) do check(false, "an error was caught and noted: " .. tostring(e.label) .. ": " .. tostring(e.message)) end
print(fails == 0 and "utils checks passed" or (fails .. " utils checks failed"))
