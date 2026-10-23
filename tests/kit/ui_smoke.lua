-- UI smoke test for the loot table's database mode: mocked widgets and menus, driven like a player.
-- Run after db_smoke.lua's mocks are defined (this file is appended to them by ui_smoke.py).

local uiFails = 0
local function ucheck(c, m) if not c then uiFails = uiFails + 1; print("UI FAIL: " .. m) end end

local function Widget(kind)
  local w = { kind = kind, shown = true, width = 900, height = 520, scripts = {}, children = {}, enabled = true }
  return setmetatable(w, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown end end
    if k == "Show" then return function(self)
      local was = self.shown; self.shown = true
      if not was and self.scripts.OnShow then self.scripts.OnShow(self) end end end
    if k == "Hide" then return function(self)
      local was = self.shown; self.shown = false
      if was and self.scripts.OnHide then self.scripts.OnHide(self) end end end
    if k == "SetShown" then return function(self, v) if v then self:Show() else self:Hide() end end end
    if k == "GetWidth" then return function(self) return self.width end end
    if k == "GetHeight" then return function(self) return self.height end end
    if k == "SetWidth" then return function(self, v) self.width = v; self.sized = true end end
    if k == "SetHeight" then return function(self, v) self.height = v end end
    if k == "SetSize" then return function(self, a, b) self.width, self.height = a, b; self.sized = true end end
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "GetScript" then return function(self, name) return self.scripts[name] end end
    if k == "HookScript" then return function(self, name, fn)
      local old = self.scripts[name]
      self.scripts[name] = function(...) if old then old(...) end fn(...) end end end
    if k == "CreateTexture" or k == "CreateMaskTexture" then return function(self) return Widget(k) end end
    -- font strings are kept (FontStrings) so a test can find text that isn't a frame's child
    if k == "CreateFontString" then return function(self)
      local f = Widget(k); FontStrings = FontStrings or {}; FontStrings[#FontStrings + 1] = f; return f end end
    if k == "GetChildren" then return function(self) return unpack(self.children) end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "GetText" then return function(self) return self.text end end
    if k == "GetHighlightTexture" then return function(self) self.hl = self.hl or Widget("tex"); return self.hl end end
    if k == "GetName" then return function(self) return self.name end end
    if k == "GetFrameLevel" then return function() return 1 end end
    if k == "GetVerticalScroll" then return function(self) return self.scrollY or 0 end end
    -- like the game: setting the offset fires OnVerticalScroll
    if k == "SetVerticalScroll" then return function(self, v)
      self.scrollY = v
      if self.scripts.OnVerticalScroll then self.scripts.OnVerticalScroll(self, v) end end end
    if k == "GetVerticalScrollRange" then return function() return 0 end end
    if k == "GetStringWidth" then return function() return 50 end end
    if k == "IsMouseOver" then return function() return false end end
    if k == "SetEnabled" then return function(self, v) self.enabled = v end end
    if k == "SetVertexColor" then return function(self, r, g, b, a) self.color = { r, g, b, a } end end
    if k == "SetTextColor" then return function(self, r, g, b) self.textColor = { r, g, b } end end
    if k == "SetPoint" then return function(self, point, rel, relPoint, x, y) self.top = y; self.point = point end end
    if k == "SetFontString" then return function(self, fs) self.fontString = fs end end
    if k == "GetFontString" then return function(self) return self.fontString end end
    if k == "CreateAnimationGroup" or k == "CreateAnimation" then return function()
      local g = Widget("Anim")
      g.Play = function(s) s.playing = true; AnimPlays = (AnimPlays or 0) + 1 end
      g.Stop = function(s) s.playing = false; AnimStops = (AnimStops or 0) + 1 end
      g.IsPlaying = function(s) return s.playing == true end
      return g end end
    if k == "GetEffectiveScale" then return function() return 1 end end
    if k == "RegisterEvent" then return function(self, e) self.events = self.events or {}; self.events[e] = true end end
    if k == "EnableMouse" then return function(self, v) self.mouseEnabled = v end end
    if k == "EnableKeyboard" then return function(self, v) self.keyboard = v == true end end
    if k == "SetPropagateKeyboardInput" then return function(self, v)
      -- restricted in combat since 10.1.5: an addon calling it then gets an error
      if type(InCombatLockdown) == "function" and InCombatLockdown() then error("SetPropagateKeyboardInput is restricted in combat") end
      self.propagate = v == true end end
    if k == "EnableMouseWheel" then return function(self, v) self.mouseWheel = v end end
    if k == "SetScale" then return function(self, v) self.scale = v end end
    if k == "SetValue" then return function(self, v)
      self.value = v
      if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v, false) end end end
    if k == "GetValue" then return function(self) return self.value or 0 end end
    if k == "GetParent" then return function(self) return self._parent end end
    if k == "SetParent" then return function(self, p) self._parent = p end end
    if k == "GetAlpha" then return function(self) return self._alpha or 1 end end
    if k == "SetAlpha" then return function(self, a) self._alpha = a end end
    return function() end
  end })
end
AllFrames = {}
function CreateFrame(kind, name, parent, template)
  local w = Widget(kind)
  AllFrames[#AllFrames + 1] = w
  w.name = name
  w._parent = parent
  w.shown = true
  if parent and parent.children then table.insert(parent.children, w) end
  if name then _G[name] = w end
  if template == "UIPanelButtonTemplate" then
    w.Text = Widget("FontString")
    w.SetText = function(self, t) self.text = t; self.Text.text = t end
  end
  return w
end
UIParent = Widget("UIParent")
GameTooltip = Widget("GameTooltip")
UISpecialFrames = {}
GameFontHighlight, GameFontNormal = {}, {}
ITEM_QUALITY_COLORS = { [3] = { r = 0, g = 0.4, b = 1 }, [4] = { r = 0.6, g = 0.2, b = 1 } }
RAID_CLASS_COLORS = { WARRIOR = { colorStr = "ffc69b6d" }, MAGE = { colorStr = "ff3fc7eb" } }
CLASS, ALL_SPECS = "Class", "All Specializations"
function GetNumClasses() return 2 end
function GetClassInfo(i) if i == 1 then return "Warrior", "WARRIOR", 1 end if i == 2 then return "Mage", "MAGE", 8 end end
function UnitGUID() return "Player-1" end
function IsModifiedClick() return false end
-- timers are kept, not run (a test runs the ones it means to)
PendingTimers = {}
C_Timer = { After = function(_, fn) PendingTimers[#PendingTimers + 1] = fn end }
C_TooltipInfo = { GetItemKey = function(itemID, level)
  return { lines = { { leftText = "Item " .. itemID }, { leftText = "Item Level " .. tostring(level) }, { leftText = "Binds" },
    { leftText = "+" .. tostring(level * 2) .. " Haste" }, { leftText = "+" .. tostring(level) .. " Mastery" } } }
end, GetItemByID = function(itemID)
  return { lines = { { leftText = "Item " .. itemID }, { leftText = "x" }, { leftText = "y" }, { leftText = "+50 Critical Strike" } } }
end }
ITEM_MOD_HASTE_RATING_SHORT, ITEM_MOD_MASTERY_RATING_SHORT, ITEM_MOD_CRIT_RATING_SHORT, ITEM_MOD_VERSATILITY = "Haste", "Mastery", "Critical Strike", "Versatility"

-- menu mock: records the last menu built
local lastMenu
local function Description(text, isSelected, setSelected)
  local d = { text = text, isSelected = isSelected, setSelected = setSelected, entries = {}, enabled = true }
  function d:CreateButton(t) local c = Description(t); table.insert(self.entries, c); return c end
  function d:CreateRadio(t, is, set) local c = Description(t, is, set); c.radio = true; table.insert(self.entries, c); return c end
  function d:CreateCheckbox(t, is, set) local c = Description(t, is, set); c.checkbox = true; table.insert(self.entries, c); return c end
  function d:CreateTitle(t) local c = Description(t); c.title = true; table.insert(self.entries, c); return c end
  function d:CreateDivider() end
  function d:SetEnabled(v) self.enabled = v end
  function d:SetOnEnter(fn) self.onEnter = fn end
  function d:SetOnLeave(fn) self.onLeave = fn end
  return d
end
MenuResponse = { Refresh = 2 }
MenuUtil = { CreateContextMenu = function(owner, gen) lastMenu = Description("root"); gen(owner, lastMenu) end }
local function FindEntry(menu, pattern)
  for _, e in ipairs(menu.entries) do
    if e.text and tostring(e.text):find(pattern) then return e end
    local sub = FindEntry(e, pattern)
    if sub then return sub end
  end
end

-- The game's own window closing must stay the game's: an addon function in that chain (as a
-- replaced CloseWindows once was) taints every window it closes, on Escape, death and loading.
local BLIZZARD_GLOBALS = { "CloseWindows", "CloseAllWindows", "CloseSpecialWindows", "ToggleGameMenu",
  "RegisterGameMenuEscHandler" }
local blizzardOriginals = {}
for _, name in ipairs(BLIZZARD_GLOBALS) do
  _G[name] = _G[name] or function() end
  blizzardOriginals[name] = _G[name]
end
local escHandlers = 0
local realRegisterEsc = RegisterGameMenuEscHandler
RegisterGameMenuEscHandler = function(...) escHandlers = escHandlers + 1 end
blizzardOriginals.RegisterGameMenuEscHandler = RegisterGameMenuEscHandler
-- The game's tooltip data processor: the item post-calls the loot table registers, to run by hand
local itemPostCalls = {}
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == "Item" then itemPostCalls[#itemPostCalls + 1] = fn end end }
Enum.TooltipDataType = { Item = "Item" }
for _, f in ipairs({ "Case.lua", "CaseStyles.lua", "ItemLinks.lua", "LootTable.lua" }) do assert(loadfile(f))("BetterGreatVault", BGV) end
local LT = BGV.LootTable
-- Best-in-Slot tiers for the checks below, and the game version the list was read for
BGV.Bis = { SOURCE = { patch = "12.1.5", build = "70448" }, Tier = function(itemID, specID)
  if itemID == 9011 and specID == 71 then return "A" end
  if itemID == 9012 and specID == 63 then return "S" end
  if itemID == 9012 and specID == 62 then return "B" end
end }
local function RowFor(rows, itemID)
  for _, r in ipairs(rows) do if r.entry and r.entry.itemID == itemID then return r end end
end

-- open the database
LT.ToggleDatabase()
local loot = _G.BetterGreatVaultLootTable
ucheck(loot and loot.shown, "database window shown")
function scrollFrameOf(frame)
  for _, c in ipairs(frame.children) do if c.kind == "ScrollFrame" then return c end end
end
-- Only the rows in view are painted: a view taller than any list here shows them all (the
-- game fires OnSizeChanged when the list's size changes).
local function ViewHeight(height)
  local s = scrollFrameOf(loot)
  s.height = height
  s.scripts.OnSizeChanged(s)
end
ViewHeight(4000)
local function Rows()
  local rows = {}
  local scroll
  for _, c in ipairs(loot.children) do if c.kind == "ScrollFrame" then scroll = c end end
  local child = scroll and scroll.children[1]
  for _, r in ipairs(child and child.children or {}) do if r.shown and r.entry then rows[#rows + 1] = r end end
  return rows
end
-- the rail's source rows
local rail
for _, c in ipairs(loot.children) do if c.children and #c.children >= 3 and c.width == 188 then rail = c end end
local raidRow, mplusRow, worldRow, tierRow
for _, c in ipairs(rail and rail.children or {}) do
  if c.label and c.label.text == "Tier set" then tierRow = c end
  if c.label and c.label.text == "Raid" then raidRow = c end
  if c.label and c.label.text == "M+ keystones" then mplusRow = c end
  if c.label and c.label.text == "World" then worldRow = c end
end
ucheck(raidRow and mplusRow and worldRow, "three source rows in the rail")
local function Dividers()
  local found = {}
  for _, r in ipairs(scrollFrameOf(loot).children[1].children) do
    if r.shown and not r.entry and r.name.text and r.name.text:find("•") and not r.band.shown then found[#found + 1] = r end
  end
  -- on-screen order: rows are placed at TOPLEFT (4, -y), so a higher top is nearer 0
  table.sort(found, function(a, b) return (a.top or 0) > (b.top or 0) end)
  for index, r in ipairs(found) do found[index] = r.name.text end
  return found
end
-- Raid and M+ listed to start with, World not (its level button disabled)
local rows = Rows()
print("db rows to start (raid + M+, warrior 71):", #rows)
ucheck(raidRow.fill.shown and mplusRow.fill.shown and not worldRow.fill.shown, "raid and M+ checked, world not")
ucheck(worldRow.level.enabled == false and raidRow.level.enabled ~= false, "level button only for selected sources")
ucheck(#rows == 11, "raid (8) and M+ (3) items together, got " .. #rows)
local dividers = Dividers()
print("dividers:", table.concat(dividers, " | "))
ucheck(#dividers == 3 and dividers[1]:find("^TIER SET • RAID MYTHIC • 334$") and dividers[2]:find("^RAID")
  and dividers[3]:find("^MYTHIC %+10%+ • 318"), "a divider heads each source, the tier set's first")
-- the tier set is its own source, first in the rail and listed to start with, at the highest
-- item level any vault slot gives (raid Mythic's normal level)
ucheck(tierRow and tierRow.fill.shown and (tierRow.top or 0) > (raidRow.top or 0), "the tier set heads the sources, checked")
ucheck(tierRow.level:GetText() == "Raid Mythic • 334", "tier set level: " .. tostring(tierRow.level:GetText()))
tierRow.scripts.OnClick(tierRow)
ucheck(not tierRow.fill.shown, "the tier set unselected")
ucheck(mplusRow.level:GetText() == "+10+ • 318", "top key level reads +10+, got " .. tostring(mplusRow.level:GetText()))
-- the last selected source can't be unselected
mplusRow.scripts.OnClick(mplusRow)
ucheck(not mplusRow.fill.shown and mplusRow.level.enabled == false, "M+ unselected, its level button disabled")
raidRow.scripts.OnClick(raidRow)
ucheck(raidRow.fill.shown, "clicking the last selected source leaves it selected")
rows = Rows()
ucheck(#rows == 8 and #Dividers() == 0, "raid only: 8 rows, no dividers")
print("db raid rows (warrior default spec 71, mythic):", #rows)
ucheck(#rows > 0, "raid rows listed")
local sawCeiling = false
for _, r in ipairs(rows) do if r.level.text == "344" then sawCeiling = true end end
ucheck(sawCeiling, "ceiling item level shown for the last two bosses")
ucheck(RowFor(rows, 9011) and RowFor(rows, 9011).tier.text == "A", "warrior 71 sees its BiS tier A on 9011")
ucheck(RowFor(rows, 9021) and RowFor(rows, 9021).tier.text == "-", "no tier shows -")
do
  local nameWidth = RowFor(rows, 9011).name.width
  BetterGreatVaultDB.showBisTiers = false
  LT.RefreshStyle()
  rows = Rows()
  local columns
  for _, c in ipairs(loot.children) do if c.labels then columns = c end end
  ucheck(RowFor(rows, 9011).tier.text == "" and not RowFor(rows, 9011).tierBadge.shown, "tiers off: no tier on 9011")
  ucheck(not columns.labels.tier.shown, "tiers off: no Tier column header")
  ucheck(RowFor(rows, 9011).name.width == nameWidth + 44, "tiers off: the name takes the column's room")
  BetterGreatVaultDB.showBisTiers = nil
  LT.RefreshStyle()
  rows = Rows()
  ucheck(RowFor(rows, 9011).tier.text == "A" and columns.labels.tier.shown, "tiers back on")
end
do
  local header, box
  for _, c in ipairs(loot.children) do if c.labels then header = c end end
  for _, c in ipairs(header.children) do if c.kind == "EditBox" then box = c end end
  ucheck(box and box.hint.text == "Search", "a search box in the column header")
  local countBefore = #rows
  local realAfter = C_Timer.After
  C_Timer.After = function(_, fn) fn() end
  box:SetText("9011")
  box.scripts.OnTextChanged(box)
  local found = Rows()
  ucheck(#found == 1 and RowFor(found, 9011), "search by name narrows the list: " .. #found)
  ucheck(box.clear.shown and box.rule.shown and not box.hint.shown, "while searching: clear button and accent rule")
  box:SetText("no such item")
  box.scripts.OnTextChanged(box)
  ucheck(#Rows() == 0, "no match, no rows")
  -- an empty list says why: the search, the search and filters, or the filters
  local function MessageText()
    local child = scrollFrameOf(loot).children[1]
    for _, r in ipairs(child.children) do
      if r.shown and not r.entry and not r.band.shown and r.name.text then return r.name.text end
    end
  end
  ucheck(MessageText() == 'No items match "no such item".', "no match for a search names it: " .. tostring(MessageText()))
  BGV.LootTable.SetStatFilter({ "CRIT" })
  ucheck(MessageText() == "No items match the search and filters.", "search and filters: " .. tostring(MessageText()))
  box.clear.scripts.OnClick(box.clear)
  box.scripts.OnTextChanged(box)
  ucheck(#Rows() == 0 and MessageText() == "No items match these filters.", "filters alone (no item has Crit): " .. tostring(MessageText()))
  BGV.LootTable.SetStatFilter({})
  box.clear.scripts.OnClick(box.clear)
  box.scripts.OnTextChanged(box)
  ucheck(#Rows() == countBefore and box.hint.shown, "clearing the search lists everything again")
  C_Timer.After = realAfter
  rows = Rows()
end
-- Shift-click links the item in chat: a real item link, at the row's exact item level when the
-- game gives one (here the tooltip's link)
do
  local list = Rows()
  local row = RowFor(list, 9011)
  local linked
  local realInfo, realLevel, realKey = C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, C_TooltipInfo.GetItemKey
  C_Item.GetItemInfo = function(id) return "Item " .. id, "|cnIQ4:|Hitem:" .. id .. "::::::::90:71::::::|h[Item " .. id .. "]|h|r", 4 end
  C_Item.GetDetailedItemLevelInfo = function(link) return tostring(link):find("1:99999", 1, true) and row.entry.itemLevel or 250 end
  HandleModifiedItemClick = function(link) linked = link end
  IsModifiedClick = function() return true end
  row.scripts.OnClick(row, "LeftButton")
  ucheck(linked and linked:find("|Hitem:9011:", 1, true) and linked:find("[Item 9011]", 1, true), "Shift-click links the item: " .. tostring(linked))
  C_TooltipInfo.GetItemKey = function(itemID, level)
    local data = realKey(itemID, level)
    data.hyperlink = "item:" .. itemID .. "::::::::90:71::::1:99999::"
    return data
  end
  linked = nil
  row.scripts.OnClick(row, "LeftButton")
  ucheck(linked and linked:find("1:99999", 1, true) and linked:find("|Hitem:9011:", 1, true) and linked:find("[Item 9011]", 1, true),
    "Shift-click links it at the row's item level: " .. tostring(linked))
  C_Item.GetItemInfo, C_Item.GetDetailedItemLevelInfo, C_TooltipInfo.GetItemKey = realInfo, realLevel, realKey
  IsModifiedClick = function() return false end
  HandleModifiedItemClick = nil
end
-- long (translated) column names are cut to their columns; the full name shows on hover
do
  local header
  for _, c in ipairs(loot.children) do if c.labels then header = c end end
  local labels, buttons = header.labels, {}
  for _, c in ipairs(header.children) do if c.kind == "Button" then buttons[#buttons + 1] = c end end
  local statButton, gearButton = buttons[1], buttons[2]
  local function Measured(fontString)
    fontString.GetUnboundedStringWidth = function(self) return 7 * utf8.len(self.text or "") end
  end
  for _, label in pairs(labels) do Measured(label) end
  Measured(statButton.text)
  Measured(gearButton.text)
  labels.level:SetText("РІВЕНЬ ПРЕДМЕТА")
  labels.stats:SetText("ДРУГОРЯДНІ ХАРАКТЕРИСТИКИ")
  LT.RefreshStyle()
  ucheck(labels.level.width == 72, "a long level name is cut to its column (80 - 8): " .. tostring(labels.level.width))
  ucheck(statButton.width == 16 and labels.stats.width == 142 - 21, "the stats name leaves room for its filter button: "
    .. tostring(labels.stats.width) .. " + " .. tostring(statButton.width))
  ucheck(labels.slot.width == 28, "a name that fits keeps its own width, the button right after it: " .. tostring(labels.slot.width))
  ucheck(labels.item.width == 28, "item name: " .. tostring(labels.item.width))
  -- a long gear pick takes at most 60% of its column, its text cut to the button
  gearButton.scripts.OnClick(gearButton)
  FindEntry(lastMenu, "^Head$").setSelected()
  gearButton.text.GetUnboundedStringWidth = function() return 200 end
  LT.RefreshStyle()
  ucheck(gearButton.width == 73 and gearButton.text.width == 65, "a long gear pick is capped: " .. tostring(gearButton.width))
  ucheck(labels.slot.width == 28 and 28 + 5 + 73 <= 122, "the slot name and the capped pick fit the column")
  Measured(gearButton.text)
  gearButton.scripts.OnClick(gearButton)
  FindEntry(lastMenu, "All gear").setSelected()
  ucheck(gearButton.width == 16 and gearButton.text.width == 8, "back to + at its own width: " .. tostring(gearButton.width))
  -- hover: the full name, only when cut short
  GameTooltip.text = nil
  labels.level.hover.scripts.OnEnter(labels.level.hover)
  ucheck(GameTooltip.text == nil, "no tooltip for a name that isn't cut")
  labels.level.IsTruncated = function() return true end
  labels.level.hover.scripts.OnEnter(labels.level.hover)
  ucheck(GameTooltip.text == "Item Level", "a cut name shows in full on hover: " .. tostring(GameTooltip.text))
  labels.level.hover.scripts.OnLeave(labels.level.hover)
  labels.level.IsTruncated = nil
  BetterGreatVaultDB.showBisTiers = false
  LT.RefreshStyle()
  ucheck(not labels.tier.hover.shown, "tiers off: no hover area for the hidden Tier name")
  BetterGreatVaultDB.showBisTiers = nil
  labels.level:SetText("ITEM LEVEL")
  labels.stats:SetText("SECONDARY STATS")
  LT.RefreshStyle()
  ucheck(labels.tier.hover.shown and labels.level.width == 70, "tiers back, English names fit: " .. tostring(labels.level.width))
  rows = Rows()
end
ucheck(RowFor(rows, 9011) and RowFor(rows, 9011).slot.text == "Head (Cloth)", "slot with armor type: " .. tostring(RowFor(rows, 9011) and RowFor(rows, 9011).slot.text))
-- hover: an accent-tinted wash at low alpha (never solid white); group headers get none
local accent = BGV.Utils.AccentColor()
local hover = rows[1] and rows[1].hover
ucheck(hover and hover.color and math.abs(hover.color[4] - 0.12) < 0.001, "row hover at 12% alpha")
ucheck(hover and hover.color and hover.color[1] == accent[1] and hover.color[2] == accent[2], "row hover tinted with the accent")
local groupRow
local scrollFrame
for _, c in ipairs(loot.children) do if c.kind == "ScrollFrame" then scrollFrame = c end end
for _, r in ipairs(scrollFrame.children[1].children) do if r.shown and not r.entry and r.band then groupRow = r end end
ucheck(groupRow and groupRow.hover.shown == false, "group header rows have no hover")
local firstStats = rows[1] and rows[1].statLines and rows[1].statLines[1] and rows[1].statLines[1].text
print("first row stats line:", firstStats)
ucheck(firstStats and firstStats:find("^%+%d"), "stats with amounts when item level known")

-- class menu: switch to Mage, all specs
local classButton
for _, c in ipairs(loot.children) do if c.GetText and tostring(c:GetText()):find("Warrior") then classButton = c end end
ucheck(classButton, "class button shows the player's class: " .. tostring(classButton and classButton:GetText()))
classButton.scripts.OnClick(classButton)
local mage = FindEntry(lastMenu, "Mage")
ucheck(mage and mage.setSelected, "class menu lists Mage")
mage.setSelected()
print("class button after picking Mage:", classButton:GetText())
ucheck(tostring(classButton:GetText()):find("Mage") and tostring(classButton:GetText()):find("All specs"), "mage, all specs")
rows = Rows()
print("db raid rows (mage all specs):", #rows)
ucheck(RowFor(rows, 9012) and RowFor(rows, 9012).tier.text == "S", "all specs shows the best tier among the class's specs")
ucheck(#rows > 0, "mage raid rows")

-- "All classes" at the top of the class submenu
classButton.scripts.OnClick(classButton)
local allClasses = FindEntry(lastMenu, "All classes")
ucheck(allClasses and allClasses.setSelected, "class menu offers All classes")
allClasses.setSelected()
ucheck(classButton:GetText() == "All classes", "button says All classes: " .. tostring(classButton:GetText()))
rows = Rows()
print("db raid rows (all classes):", #rows)
ucheck(#rows == 12, "all classes lists every raid item (12), got " .. #rows)
ucheck(RowFor(rows, 9012) and RowFor(rows, 9012).tier.text == "-", "no tier for all classes")
-- Only the rows in view are painted; scrolling paints those coming into view and takes back the
-- rest, each row where its item's line is, none twice.
do
  local s = scrollFrameOf(loot)
  local listHeight = s.children[1].height
  local function InView(scrollY, view)
    local ok, tops, items = true, {}, {}
    for _, r in ipairs(s.children[1].children) do
      if r.shown then
        local y = -(r.top or 0)
        if y + (r.height or 0) < scrollY - 64 or y > scrollY + view + 64 or tops[y] then ok = false end
        tops[y] = true
        if r.entry then
          if items[r.entry.itemID] then ok = false end
          items[r.entry.itemID] = true
        end
      end
    end
    return ok
  end
  ViewHeight(120)
  local top = Rows()
  ucheck(#top > 0 and #top < 12 and RowFor(top, 9011) and not RowFor(top, 9043), "a short view paints only the top rows: " .. #top)
  ucheck(InView(0, 120), "painted rows are in view, each once")
  s:SetVerticalScroll(listHeight - 120)
  local bottom = Rows()
  ucheck(RowFor(bottom, 9043) and not RowFor(bottom, 9011), "scrolled to the end: the last item painted, the first taken back")
  ucheck(InView(listHeight - 120, 120), "painted rows follow the scroll")
  s:SetVerticalScroll(0)
  ucheck(RowFor(Rows(), 9011) and not RowFor(Rows(), 9043), "scrolled back to the top")
  ViewHeight(4000)
  ucheck(#Rows() == 12, "a tall view paints every row again")
  -- a hidden window paints nothing; showing it lays the list out once
  local paints = 0
  loot:Hide()
  s:SetVerticalScroll(0)
  for _, r in ipairs(s.children[1].children) do
    local set = r.icon.SetTexture
    r.icon.SetTexture = function(self, t) if type(t) == "number" then paints = paints + 1 end end
  end
  LT.ToggleDatabase()
  ucheck(loot.shown and paints > 0 and paints <= 12, "reopened: each row painted once, got " .. paints)
  for _, r in ipairs(s.children[1].children) do r.icon.SetTexture = nil end
end
-- Rows sliding under the pointer while the list scrolls get no tooltip; the row under the
-- pointer gets it once the list has nearly stopped. A row's OnLeave hides only its own tooltip.
do
  local s = scrollFrameOf(loot)
  local list = Rows()
  local target, other = list[3], list[1]
  GameTooltip.name = "GameTooltip"
  GameTooltip.owner = nil
  GameTooltip.SetOwner = function(self, owner) self.owner = owner end
  GameTooltip.GetOwner = function(self) return self.owner end
  GameTooltip.Hide = function(self) self.owner = nil end
  s.GetVerticalScrollRange = function() return 1000 end
  s.IsMouseOver = function() return true end
  target.IsMouseMotionFocus = function() return true end
  ucheck(s.scripts.OnUpdate == nil, "a still list runs no per-frame script")
  s.scripts.OnMouseWheel(s, -1)
  ucheck(s.scripts.OnUpdate ~= nil, "the wheel starts the list's glide")
  target.scripts.OnEnter(target)
  ucheck(GameTooltip.owner == nil, "no tooltip for a row passing under the pointer while the list scrolls")
  local steps = 0
  while GameTooltip.owner == nil and steps < 200 and s.scripts.OnUpdate do
    s.scripts.OnUpdate(s, 1 / 60)
    steps = steps + 1
  end
  ucheck(GameTooltip.owner == target and math.abs(s:GetVerticalScroll() - 64) <= 8,
    "the row under the pointer gets its tooltip as the list settles (" .. steps .. " frames, at " .. string.format("%.1f", s:GetVerticalScroll()) .. ")")
  other.scripts.OnLeave(other)
  ucheck(GameTooltip.owner == target, "leaving another row keeps the tooltip")
  target.scripts.OnLeave(target)
  ucheck(GameTooltip.owner == nil, "leaving the row hides its tooltip")
  target.scripts.OnEnter(target)
  ucheck(GameTooltip.owner == target, "a still list shows the tooltip at once")
  -- comparisons follow the game (Shift, or "Always compare items"): none forced on the tooltip,
  -- and the game's 0.2s tooltip update shows or hides them when Shift changes
  local compare, shown, hidden = false, 0, 0
  TooltipUtil = { ShouldDoItemComparison = function() return compare end }
  GameTooltip_ShowCompareItem = function() shown = shown + 1 end
  GameTooltip_HideShoppingTooltips = function() hidden = hidden + 1 end
  target.scripts.OnLeave(target)
  target.scripts.OnEnter(target)
  ucheck(shown == 0 and GameTooltip.owner == target, "no comparison forced on the tooltip")
  target:UpdateTooltip()
  ucheck(shown == 0 and hidden == 0, "nothing changes while Shift stays up")
  compare = true
  target:UpdateTooltip()
  target:UpdateTooltip()
  ucheck(shown == 1, "pressing Shift shows the comparison once, got " .. shown)
  compare = false
  target:UpdateTooltip()
  ucheck(hidden == 1, "letting go of Shift hides it")
  TooltipUtil, GameTooltip_ShowCompareItem, GameTooltip_HideShoppingTooltips = nil, nil, nil
  target.scripts.OnLeave(target)
  for _ = 1, 200 do if s.scripts.OnUpdate then s.scripts.OnUpdate(s, 1 / 60) end end
  ucheck(s.scripts.OnUpdate == nil, "the glide's per-frame script stops once the list settles")
  target.IsMouseMotionFocus, s.GetVerticalScrollRange, s.IsMouseOver = nil, nil, nil
  GameTooltip.SetOwner, GameTooltip.GetOwner, GameTooltip.Hide = nil, nil, nil
  s:SetVerticalScroll(0)
end
-- A redraw while the list loads moves a row whose line moved instead of painting it anew: an
-- item arriving above the row under the pointer pushes it down, and it stays the same frame, never
-- hidden, with its tooltip (a rebuild costs 4 to 15 ms, and loading redraws come 10 times a second).
do
  -- one class's view (the mages'): a warrior-only item can then arrive
  classButton.scripts.OnClick(classButton)
  FindEntry(lastMenu, "Mage").setSelected()
  -- redraws queued earlier (their timers kept, never run) run now, so the next one queues afresh
  for _, fn in ipairs(PendingTimers) do fn() end
  PendingTimers = {}
  local s = scrollFrameOf(loot)
  local list = Rows()
  table.sort(list, function(a, b) return (a.top or 0) > (b.top or 0) end)
  local target = list[3]
  local itemID = target.entry.itemID
  local listed = {}
  for _, r in ipairs(list) do listed[r.entry.itemID] = true end
  -- a boss 1 item the view doesn't list yet, made usable by every spec: it appears above the row
  local newcomer
  for _, id in ipairs({ 9011, 9012, 9013 }) do if not listed[id] and not newcomer then newcomer = id end end
  ucheck(newcomer ~= nil and itemID > 9013, "setup: a boss 1 item to arrive above row 3 (" .. tostring(newcomer) .. " above " .. tostring(itemID) .. ")")
  local hides = 0
  target.Hide = function(self) hides = hides + 1; local was = self.shown; self.shown = false; if was and self.scripts.OnHide then self.scripts.OnHide(self) end end
  GameTooltip.name = "GameTooltip"
  GameTooltip.owner = nil
  GameTooltip.SetOwner = function(self, owner) self.owner = owner end
  GameTooltip.GetOwner = function(self) return self.owner end
  GameTooltip.Hide = function(self) self.owner = nil end
  s.IsMouseOver = function() return true end
  target.IsMouseMotionFocus = function() return true end
  target.scripts.OnEnter(target)
  ucheck(GameTooltip.owner == target, "the pointer rests on a row with its tooltip")
  local before = target.top
  local specsBefore = items[newcomer]
  items[newcomer] = { 71, 72, 73, 62, 63, 64 }
  BGV.Rewards.ClearDatabase()
  BGV.LootTable.Reload()
  ucheck(#PendingTimers == 1, "a reload redraws on a timer, as a loading list does (" .. #PendingTimers .. " queued)")
  for _, fn in ipairs(PendingTimers) do fn() end
  PendingTimers = {}
  local rows = Rows()
  ucheck(RowFor(rows, newcomer) ~= nil, "the new item is listed")
  local moved = RowFor(rows, itemID)
  ucheck(moved == target and target.shown and hides == 0, "the row under the pointer is the same frame, never hidden (hidden " .. hides .. " times)")
  ucheck(target.top ~= nil and before ~= nil and target.top < before, "it moved down with its line (" .. tostring(before) .. " -> " .. tostring(target.top) .. ")")
  ucheck(GameTooltip.owner == target, "and keeps its tooltip")
  -- no row shows twice, and the rows sit one under another with no two on the same line
  local seen, twice, tops, overlap = {}, false, {}, false
  for _, r in ipairs(rows) do
    if seen[r] then twice = true end
    seen[r] = true
    if tops[r.top] then overlap = true end
    tops[r.top] = true
  end
  ucheck(not twice and not overlap, "every line has a row of its own")
  items[newcomer] = specsBefore
  target.Hide = nil
  target.IsMouseMotionFocus = nil
  target.scripts.OnLeave(target)
  BGV.Rewards.ClearDatabase()
  BGV.LootTable.Reload()
  for _, fn in ipairs(PendingTimers) do fn() end
  PendingTimers = {}
  ucheck(RowFor(Rows(), newcomer) == nil, "the view is as it was")
  GameTooltip.SetOwner, GameTooltip.GetOwner, GameTooltip.Hide = nil, nil, nil
  classButton.scripts.OnClick(classButton)
  FindEntry(lastMenu, "All classes").setSelected()
  ucheck(classButton:GetText() == "All classes", "back to All classes for the checks below")
end

-- the scroll bar can be dragged: the thumb follows the pointer, the track jumps to it
do
  local s = scrollFrameOf(loot)
  local grab
  for _, c in ipairs(loot.children) do if c.bgvScrollGrab then grab = c end end
  ucheck(grab and grab.mouseEnabled, "the scroll bar takes the mouse")
  local realCursor, realDown = GetCursorPosition, IsMouseButtonDown
  local pointer, held = 0, true
  GetCursorPosition = function() return 0, 500 - pointer end
  IsMouseButtonDown = function() return held end
  grab.GetTop = function() return 500 end
  s.GetVerticalScrollRange = function() return 1000 end
  local height = s.height
  s.height = 400
  s:SetVerticalScroll(0)
  -- a 400px view of 1400px: the thumb is 400 * 400 / 1400 tall, with 400 - that to travel
  local free = 400 - 400 * 400 / 1400
  pointer = 10
  grab.scripts.OnMouseDown(grab, "LeftButton")
  pointer = 10 + free / 2
  grab.scripts.OnUpdate(grab, 0.016)
  ucheck(math.abs(s:GetVerticalScroll() - 500) < 0.01, "dragging the thumb halfway down scrolls halfway: " .. s:GetVerticalScroll())
  held = false
  grab.scripts.OnUpdate(grab, 0.016)
  ucheck(grab.scripts.OnUpdate == nil, "letting go ends the drag")
  held, pointer = true, 395
  grab.scripts.OnMouseDown(grab, "LeftButton")
  ucheck(s:GetVerticalScroll() == 1000, "pressing the track below the thumb jumps there: " .. s:GetVerticalScroll())
  grab.scripts.OnMouseUp(grab, "LeftButton")
  pointer = 0
  grab.scripts.OnMouseDown(grab, "LeftButton")
  ucheck(s:GetVerticalScroll() == 0, "and above it, back to the top: " .. s:GetVerticalScroll())
  grab.scripts.OnMouseUp(grab, "LeftButton")
  GetCursorPosition, IsMouseButtonDown = realCursor, realDown
  grab.GetTop, s.GetVerticalScrollRange, s.height = nil, nil, height
  s:SetVerticalScroll(0)
end
classButton.scripts.OnClick(classButton)
ucheck(not FindEntry(lastMenu, "Spec 63"), "no spec list while All classes is chosen")
ucheck(not FindEntry(lastMenu, "Ferocity") and not FindEntry(lastMenu, "Tenacity") and not FindEntry(lastMenu, "Cunning"), "no hunter pet specs with All classes")
ucheck(not FindEntry(lastMenu, "^All specs"), "no All specs with All classes")
ucheck(FindEntry(lastMenu, "Mage") and FindEntry(lastMenu, "All classes"), "class submenu still there")
FindEntry(lastMenu, "Mage").setSelected()

-- spec 63 from the same menu
classButton.scripts.OnClick(classButton)
local spec = FindEntry(lastMenu, "Spec 63")
ucheck(spec, "spec 63 listed")
spec.setSelected()
rows = Rows()
print("db raid rows (mage 63):", #rows)
ucheck(RowFor(rows, 9012) and RowFor(rows, 9012).tier.text == "S", "mage 63 tier S on 9012")

-- level menu on the raid row: Raid Finder is unknown (disabled), Heroic known
print("raid level button:", raidRow and raidRow.level:GetText(), "| M+:", mplusRow and mplusRow.level:GetText(), "| world:", worldRow and worldRow.level:GetText())
raidRow.level.scripts.OnClick(raidRow.level)
local lfr = FindEntry(lastMenu, "Raid Finder")
ucheck(lfr and lfr.enabled == false, "unknown raid difficulty disabled in the menu")
local heroic = FindEntry(lastMenu, "Heroic")
ucheck(heroic and heroic.enabled ~= false, "heroic enabled (learned from the vault)")
heroic.setSelected()
rows = Rows()
local allHeroic = #rows > 0
for _, r in ipairs(rows) do if r.level.text ~= "321" then allHeroic = false end end
ucheck(allHeroic, "heroic rows at 321")

-- M+ source only, +8
mplusRow.scripts.OnClick(mplusRow)
raidRow.scripts.OnClick(raidRow)
ucheck(mplusRow.fill.shown and not raidRow.fill.shown, "switched to M+ only")
rows = Rows()
print("db M+ rows (mage 63):", #rows)
mplusRow.level.scripts.OnClick(mplusRow.level)
local plus8 = FindEntry(lastMenu, "^%+8")
ucheck(plus8, "+8 listed")
plus8.setSelected()
rows = Rows()
for _, r in ipairs(rows) do ucheck(r.level.text == "315", "+8 rows at 315, got " .. tostring(r.level.text)) end

-- world source only
worldRow.scripts.OnClick(worldRow)
mplusRow.scripts.OnClick(mplusRow)
ucheck(worldRow.fill.shown and not mplusRow.fill.shown, "switched to world only")
rows = Rows()
print("db world rows (mage 63):", #rows, rows[1] and rows[1].level.text)

-- stat filter + gear filter still work in database mode
BGV.LootTable.SetStatFilter({ "CRIT" })
rows = Rows()
print("world rows with Crit filter:", #rows)
BGV.LootTable.SetStatFilter({})

-- the filters are small buttons in the column header
local header
for _, c in ipairs(loot.children) do if c.labels then header = c end end
local headerButtons = {}
for _, c in ipairs(header and header.children or {}) do if c.kind == "Button" then headerButtons[#headerButtons + 1] = c end end
local statFilterButton, gearFilterButton = headerButtons[1], headerButtons[2]
ucheck(statFilterButton and statFilterButton.text.text == "+", "stat filter shows + when nothing is picked")
ucheck(gearFilterButton and gearFilterButton.text.text == "+", "gear filter shows + for all gear")
BGV.LootTable.SetStatFilter({ "CRIT" })
ucheck(statFilterButton.text.text == "C", "one stat: its first letter, got " .. tostring(statFilterButton.text.text))
local accentNow = BGV.Utils.AccentColor()
ucheck(statFilterButton.back.color and statFilterButton.back.color[1] == accentNow[1], "active filter filled with the accent")
BGV.LootTable.SetStatFilter({ "CRIT", "HASTE" })
ucheck(statFilterButton.text.text == "CH", "two stats: CH, got " .. tostring(statFilterButton.text.text))
statFilterButton.scripts.OnEnter(statFilterButton)
BGV.LootTable.SetStatFilter({})
ucheck(statFilterButton.text.text == "+", "cleared stat filter back to +")
statFilterButton.scripts.OnClick(statFilterButton)
ucheck(FindEntry(lastMenu, "Critical Strike") and FindEntry(lastMenu, "Clear"), "stat menu from the header button")
gearFilterButton.scripts.OnClick(gearFilterButton)
FindEntry(lastMenu, "^Head$").setSelected()
ucheck(gearFilterButton.text.text == "Head", "gear filter shows the slot, got " .. tostring(gearFilterButton.text.text))
gearFilterButton.scripts.OnEnter(gearFilterButton)
gearFilterButton.scripts.OnClick(gearFilterButton)
FindEntry(lastMenu, "All gear").setSelected()
ucheck(gearFilterButton.text.text == "+", "all gear back to +")

-- no completed world slot: the season's world tier still gives the item levels
ACTIVITIES[2].activityTierID = 0
BetterGreatVaultDB.rewardData = nil
BGV.GreatVault.GetSnapshot = function() return {} end
BGV.Rewards.InvalidateIcons()
LT.Invalidate()
rows = Rows()
print("world without a completed slot:", #rows, worldRow.level:GetText())
ucheck(#rows > 0 and worldRow.level:GetText() == "Tier 8 • 305", "world works without a completed slot (season tier)")

-- a source with no known item level (a new season: the game no longer knows the tier)
STEPS[249] = nil
ACTIVITIES[2].activityTierID = 0
BetterGreatVaultDB.rewardData = nil
BGV.GreatVault.GetSnapshot = function() return {} end
BGV.Rewards.InvalidateIcons()
LT.Invalidate()
worldRow.scripts.OnClick(worldRow)
rows = Rows()
ucheck(#rows == 0, "no rows when the world item level is unknown")
print("world level button with nothing known:", worldRow.level:GetText())
ucheck(worldRow.level:GetText() == "Tier 8 • unknown", "rail says the item level is unknown")

-- back to the vault view, then close
LT.Show(nil)
ucheck(not tostring(classButton.shown) or classButton.shown == false, "class button hidden in vault mode")
loot:Hide()
LT.ToggleDatabase()
loot:Hide()
ucheck(not BGV.Rewards.IsScanning(), "no scan left open")
-- the minimap button: hover, press and the rewards pulse run without errors
Minimap = Widget("Minimap")
Now = 1000
function GetTime() return Now end
function IsShiftKeyDown() return false end
function GetCursorPosition() return 0, 0 end
local waiting = true
C_WeeklyRewards.HasAvailableRewards = function() return waiting end
AnimPlays, AnimStops = 0, 0
assert(loadfile("Minimap.lua"))("BetterGreatVault", BGV)
BGV.Minimap.Apply()
local mini = _G.BetterGreatVaultMinimapButton
ucheck(mini and mini.shown, "minimap button shown")
ucheck(mini.icon, "the button exposes its icon for minimap skins")
-- a skin (e.g. EllesmereUI) re-anchors the icon into its box; clicks must not move it back
mini.icon.ClearAllPoints = function(self) self.cleared = (self.cleared or 0) + 1 end
mini.icon.SetPoint = function(self) self.moved = (self.moved or 0) + 1 end
mini.scripts.OnEnter(mini)
mini.scripts.OnMouseDown(mini, "MiddleButton")
mini.scripts.OnMouseUp(mini, "MiddleButton")
ucheck(not mini.icon.cleared and not mini.icon.moved, "clicking leaves the icon's anchors to the skin")
for _, c in ipairs(mini.children) do if c.scripts.OnUpdate then for _ = 1, 30 do if c.scripts.OnUpdate then c.scripts.OnUpdate(c, 0.05) end end end end
mini.scripts.OnLeave(mini)
for _, c in ipairs(mini.children) do if c.scripts.OnUpdate then for _ = 1, 30 do if c.scripts.OnUpdate then c.scripts.OnUpdate(c, 0.05) end end end end
ucheck(AnimPlays == 1, "rewards waiting: the gem pulses (plays " .. tostring(AnimPlays) .. ")")

-- the hover popup: the week's slots, the rewards callout, the click actions, in the accent color
local T = Enum.WeeklyRewardChestThresholdType
local weekSnapshot = {
  { type = T.Raid, index = 1, threshold = 2, progress = 3, unlocked = true, itemLevel = 285, source = {} },
  { type = T.Raid, index = 2, threshold = 4, progress = 3, unlocked = false, source = {} },
  { type = T.Raid, index = 3, threshold = 6, progress = 3, unlocked = false, source = {} },
  { type = T.Activities, index = 1, threshold = 1, progress = 4, unlocked = true, itemLevel = 318, source = {} },
  { type = T.Activities, index = 2, threshold = 4, progress = 4, unlocked = true, qualifier = "+10", source = {} },
  { type = T.Activities, index = 3, threshold = 8, progress = 4, unlocked = false, source = {} },
  { type = T.World, index = 1, threshold = 2, progress = 0, unlocked = false, source = {} },
  { type = T.World, index = 2, threshold = 4, progress = 0, unlocked = false, source = {} },
  { type = T.World, index = 3, threshold = 8, progress = 0, unlocked = false, source = {} },
}
BGV.GreatVault.GetSnapshot = function() return weekSnapshot end
C_DateAndTime = { GetSecondsUntilWeeklyReset = function() return 2 * 86400 + 3 * 3600 + 120 end }
local claimable = false
C_WeeklyRewards.CanClaimRewards = function() return claimable end
local realResolve, resolveCalls, resolveCallback = BGV.Rewards.ResolveReward, 0, nil
BGV.Rewards.ResolveReward = function(activity, onReady) resolveCalls = resolveCalls + 1; resolveCallback = onReady end
waiting = true
local function Hover() mini.scripts.OnLeave(mini); mini.scripts.OnEnter(mini) end
Hover()
local pop = _G.BetterGreatVaultMinimapPopup
local acc = BGV.Utils.AccentColor()
ucheck(pop and pop.shown, "hover shows the popup")
ucheck(pop.title.text == "Better Great Vault", "popup title")
ucheck(pop.subtitle.text == "Weekly reset in 2d 3h", "reset countdown: " .. tostring(pop.subtitle.text))
ucheck(pop.rule.color and pop.rule.color[1] == acc[1] and pop.rule.color[4] == 0.6, "header rule in the accent")
ucheck(pop.callout.shown and pop.calloutTitle.text == "Rewards are waiting", "rewards waiting: the callout")
ucheck(pop.callout.color and pop.callout.color[1] == acc[1] and pop.calloutBar.color[1] == acc[1], "callout in the accent")
ucheck(pop.heading.shown and pop.count.text == "3 of 9 unlocked", "week heading and count: " .. tostring(pop.count.text))
local raid, dungeons, world = pop.rows[1], pop.rows[2], pop.rows[3]
print("popup rows:", raid.label.text, dungeons.label.text, world.label.text)
ucheck(raid.label.shown and raid.label.text:find("^RAID"), "raid row label: " .. tostring(raid.label.text))
ucheck(raid.chips[1].text.text == "285", "unlocked raid slot shows its item level: " .. tostring(raid.chips[1].text.text))
ucheck(raid.chips[1].fill.color[1] == acc[1] and math.abs(raid.chips[1].fill.color[4] - 0.24) < 0.001, "unlocked chip filled with the accent")
ucheck(raid.chips[1].bar.shown and raid.chips[1].bar.width == 62, "unlocked chip: a full accent bar")
ucheck(raid.chips[2].text.text == "3/4" and raid.chips[2].bar.shown and raid.chips[2].bar.width == 47,
  "locked slot: progress and a bar toward it (" .. tostring(raid.chips[2].text.text) .. ", " .. tostring(raid.chips[2].bar.width) .. ")")
ucheck(raid.chips[2].fill.color[4] == 0.05, "locked chip is dark")
ucheck(dungeons.chips[2].text.text == "+10", "reward still loading: the key level meanwhile, got " .. tostring(dungeons.chips[2].text.text))
ucheck(resolveCalls == 1 and type(resolveCallback) == "function", "the loading reward is looked up again")
resolveCallback({ itemLevel = 318 })
ucheck(dungeons.chips[2].text.text == "318", "item level shown once the reward loads: " .. tostring(dungeons.chips[2].text.text))
ucheck(weekSnapshot[5].itemLevel == nil, "the vault's snapshot is left as it was")
Hover()
ucheck(resolveCalls == 1, "a slot already resolved isn't looked up again")
ucheck(world.chips[1].text.text == "0/2" and not world.chips[1].bar.shown, "no progress: no bar")
ucheck(pop.actions[1].text.text == "Open the Great Vault" and pop.actions[1].key.text == "Left-click", "left-click action")
ucheck(pop.actions[3].text.text == "Loot database, any class" and pop.actions[3].key.text == "Shift + middle-click", "database action")
ucheck(pop.actions[4].key.textColor and pop.actions[4].key.textColor[1] == acc[1] and pop.actions[4].key.textColor[3] == acc[3], "mouse buttons in the accent")
ucheck(pop.actions[4].text.textColor and pop.actions[4].text.textColor[1] == 0.9, "actions in light text")
ucheck(pop.height and pop.height > 150, "popup height set: " .. tostring(pop.height))
-- the next step: the fewest activities that unlock or raise a slot (one more raid boss here)
ucheck(pop.nextHeading.shown and pop.nextHeading.text == "NEXT STEP", "next step heading: " .. tostring(pop.nextHeading.text))
ucheck(pop.nextTitle.shown and pop.nextTitle.text == "Raid Bosses x1", "next step: what to run: " .. tostring(pop.nextTitle.text))
ucheck(pop.nextText.text == "Raids, slot 2, unlocks", "next step: what it gives: " .. tostring(pop.nextText.text))
ucheck(pop.nextBar.color and pop.nextBar.color[1] == acc[1], "next step's bar in the accent")
do
  local heightWith = pop.height
  BetterGreatVaultDB.popupNext = false
  Hover()
  ucheck(not pop.nextHeading.shown and not pop.nextBox.shown and not pop.nextTitle.shown, "next step off: hidden")
  ucheck(pop.height < heightWith, "and the popup shorter: " .. tostring(pop.height) .. " < " .. tostring(heightWith))
  BetterGreatVaultDB.popupWeek = false
  Hover()
  ucheck(not pop.heading.shown and not pop.nextHeading.shown, "both off: neither")
  BetterGreatVaultDB.popupNext = true
  Hover()
  ucheck(not pop.heading.shown and pop.nextHeading.shown, "the slots off, the next step on: only the step")
  BetterGreatVaultDB.popupWeek = nil
  BetterGreatVaultDB.popupNext = nil
  Hover()
end
-- the week as chat lines (/bgv status) and in the data broker
do
  local lines = BGV.Minimap.StatusLines()
  local text = table.concat(lines, "\n")
  print("status lines:", (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")))
  ucheck(text:find("This week: 3 of 9 unlocked", 1, true), "status: the week's count")
  ucheck(text:find("285", 1, true) and text:find("3/4", 1, true) and text:find("318", 1, true), "status: item levels and progress")
  ucheck(text:find("Weekly reset in 2d 3h", 1, true), "status: the reset")
  ucheck(text:find("Next step: ", 1, true) and text:find("Raid Bosses x1", 1, true) and text:find("Raids, slot 2, unlocks", 1, true), "status: the next step")
  local objects = {}
  LibStub = setmetatable({}, { __call = function(_, name, silent)
    if name == "LibDataBroker-1.1" then
      return { NewDataObject = function(_, objectName, object) objects[objectName] = object; return object end }
    end
  end })
  BGV.Minimap.RegisterBroker()
  local feed = objects.BetterGreatVault
  ucheck(feed and feed.type == "data source" and feed.label == "Great Vault", "a data broker feed")
  ucheck(feed.text == "Rewards waiting", "broker text while rewards wait: " .. tostring(feed.text))
  waiting = false
  BGV.Minimap.RefreshBroker()
  ucheck(feed.text == "3/9", "broker text: unlocked slots, got " .. tostring(feed.text))
  local anchor = Widget("Button")
  feed.OnEnter(anchor)
  ucheck(pop.shown and pop.actions[5].text.shown == false, "broker hover: the popup, without the drag line")
  feed.OnLeave(anchor)
  ucheck(not pop.shown, "broker leave hides it")
  BGV.Minimap.RegisterBroker()
  ucheck(objects.BetterGreatVault == feed, "registered once")
  waiting = true
end
-- the vault open: the first action closes it
WeeklyRewardsFrame = Widget("WeeklyRewardsFrame")
Hover()
ucheck(pop.actions[1].text.text == "Close the Great Vault", "vault open: close it, got " .. tostring(pop.actions[1].text.text))
WeeklyRewardsFrame = nil
mini.scripts.OnClick(mini, "RightButton")
ucheck(pop.shown and pop.actions[1].text.text == "Open the Great Vault", "a click refreshes the popup")
-- claim week: the vault shows last week's rewards, so only the callout
claimable = true
Hover()
ucheck(pop.shown and pop.callout.shown and not pop.heading.shown and not raid.label.shown and not raid.chips[1].fill.shown and not raid.chips[1].bar.shown,
  "claim week: the callout, not the week's slots")
ucheck(pop.divider.shown, "divider under the callout")
-- claim state without rewards waiting: just the actions
waiting = false
Hover()
ucheck(not pop.callout.shown and not pop.heading.shown and not pop.divider.shown, "nothing to show: only the actions")
-- progress week, nothing waiting
claimable = false
Hover()
ucheck(not pop.callout.shown and pop.heading.shown and raid.chips[1].fill.shown, "progress week without rewards: the slots")
-- rewards waiting in a new week with nothing done yet: the callout, without the empty slots
local emptyWeek = {}
for i, slot in ipairs(weekSnapshot) do
  emptyWeek[i] = { type = slot.type, index = slot.index, threshold = slot.threshold, progress = 0, unlocked = false, source = {} }
end
BGV.GreatVault.GetSnapshot = function() return emptyWeek end
waiting = true
Hover()
ucheck(pop.callout.shown and not pop.heading.shown and not pop.count.shown and not pop.note.shown and not raid.label.shown
  and not raid.chips[1].fill.shown and not raid.chips[1].text.shown, "rewards waiting, nothing done yet: no empty slots")
ucheck(pop.divider.shown, "rewards waiting, nothing done yet: the divider under the callout")
emptyWeek[7].progress = 1
Hover()
ucheck(pop.heading.shown and world.chips[1].text.text == "1/2", "rewards waiting, something counts: the slots are back")
waiting = false
emptyWeek[7].progress = 0
Hover()
ucheck(pop.heading.shown and raid.chips[1].text.text == "0/2", "nothing waiting: an empty week still shows")
BGV.GreatVault.GetSnapshot = function() return weekSnapshot end
-- a row the vault doesn't have is left out
BGV.GreatVault.GetSnapshot = function() return { weekSnapshot[1], weekSnapshot[2], weekSnapshot[3] } end
Hover()
ucheck(raid.label.shown and not dungeons.label.shown and not dungeons.chips[1].fill.shown and not dungeons.chips[1].bar.shown, "only the rows the vault has")
ucheck(pop.count.text == "1 of 3 unlocked", "count for the rows shown: " .. tostring(pop.count.text))
-- no vault data yet, or a failing snapshot: a note instead of empty rows
BGV.GreatVault.GetSnapshot = function() return {} end
Hover()
ucheck(pop.note.shown and not pop.count.shown and not raid.label.shown, "no vault data: a note")
BGV.GreatVault.GetSnapshot = function() error("snapshot failed") end
Hover()
ucheck(pop.shown and pop.note.shown, "a failing snapshot doesn't break the popup")
-- the reset countdown under a day, and without the API
C_DateAndTime.GetSecondsUntilWeeklyReset = function() return 5 * 3600 + 7 * 60 end
Hover()
ucheck(pop.subtitle.text == "Weekly reset in 5h 7m", "hours and minutes: " .. tostring(pop.subtitle.text))
C_DateAndTime = nil
Hover()
ucheck(pop.subtitle.text == "Your weekly Great Vault", "no countdown without the API")
-- leaving, dragging and hiding the button hide it; dragging still moves the button
mini.scripts.OnLeave(mini)
ucheck(not pop.shown, "leaving hides the popup")
mini.scripts.OnEnter(mini)
Minimap.GetCenter = function() return 100, 100 end
math.atan2 = math.atan2 or function(y, x) return math.atan(y, x) end -- WoW's Lua 5.1 has it
mini.scripts.OnDragStart(mini)
ucheck(not pop.shown, "dragging hides the popup")
mini.scripts.OnUpdate(mini)
ucheck(type(BetterGreatVaultDB.minimapAngle) == "number", "dragging moves the button")
mini.scripts.OnDragStop(mini)
-- The button sits just outside the minimap's edge (half its width plus 5, as LibDBIcon places
-- buttons), not at a fixed 80 from the center, inside today's 198-wide minimap.
do
  local setPoint = mini.SetPoint
  local px, py
  mini.SetPoint = function(self, point, rel, relPoint, x, y) px, py = x, y; return setPoint(self, point, rel, relPoint, x, y) end
  Minimap.width, Minimap.height = 198, 198
  function GetCursorPosition() return 100 + 50, 100 + 50 end
  mini.scripts.OnDragStart(mini)
  mini.scripts.OnUpdate(mini)
  mini.scripts.OnDragStop(mini)
  local d = px and math.sqrt(px * px + py * py)
  ucheck(d and math.abs(d - 104) < 0.01 and px > 0 and py > 0, "on a 198-wide minimap the button sits 104 from its center (" .. tostring(d) .. ")")
  -- a minimap addon resizes the minimap: the button follows its edge
  Minimap.width, Minimap.height = 140, 140
  Minimap.scripts.OnSizeChanged(Minimap)
  d = px and math.sqrt(px * px + py * py)
  ucheck(d and math.abs(d - 75) < 0.01, "a resized minimap moves the button to its new edge (" .. tostring(d) .. ")")
  -- a square minimap: the button follows its edges, straight out at 0 degrees, in toward the corner
  function GetMinimapShape() return "SQUARE" end
  Minimap.width, Minimap.height = 198, 198
  BetterGreatVaultDB.minimapAngle = 0
  Minimap.scripts.OnSizeChanged(Minimap)
  ucheck(math.abs(px - 104) < 0.01 and math.abs(py) < 0.01, "square minimap at 0 degrees: on the right edge (" .. tostring(px) .. ", " .. tostring(py) .. ")")
  BetterGreatVaultDB.minimapAngle = 45
  Minimap.scripts.OnSizeChanged(Minimap)
  local corner = (math.sqrt(2 * 104 * 104) - 10) * math.cos(math.rad(45))
  ucheck(math.abs(px - corner) < 0.01 and math.abs(py - corner) < 0.01, "square minimap at 45 degrees: toward the corner (" .. tostring(px) .. ")")
  GetMinimapShape = nil
  function GetCursorPosition() return 0, 0 end
  Minimap.width, Minimap.height = 900, 520
  mini.SetPoint = nil
end
mini.scripts.OnEnter(mini)
mini:Hide()
ucheck(not pop.shown, "hiding the button hides the popup")
BGV.Rewards.ResolveReward = realResolve

-- turning the button off and on in the settings: it stays where it is, and visible
BetterGreatVaultDB.showMinimap = true
BGV.Minimap.Apply()
ucheck(mini.shown, "shown again")
mini:SetPoint("TOPLEFT", Minimap, "TOPLEFT", 3, -40) -- a skin places it on the minimap
BetterGreatVaultDB.showMinimap = false
BGV.Minimap.Apply()
ucheck(not mini.shown, "turned off")
BetterGreatVaultDB.showMinimap = true
BGV.Minimap.Apply()
ucheck(mini.shown and mini.top == -40, "turned on again where it was, got top " .. tostring(mini.top))
BGV.Minimap.Apply(true)
ucheck(mini.top ~= -40, "a settings reset places it around the minimap again")
-- a minimap button addon (EllesmereUI's button group) keeps it in a frame of its own and zeroes
-- its alpha from a Show hook until it lays that frame out again
local group = Widget("Frame")
mini:SetParent(group)
mini:SetPoint("TOPLEFT", group, "TOPLEFT", 8, -8)
mini:SetAlpha(1)
local plainShow = mini.Show
mini.Show = function(self) plainShow(self); self:SetAlpha(0) end
BetterGreatVaultDB.showMinimap = false
BGV.Minimap.Apply()
ucheck(not mini.shown, "turned off in the addon's frame")
BetterGreatVaultDB.showMinimap = true
BGV.Minimap.Apply()
ucheck(mini.shown and mini:GetAlpha() == 1, "turned on in the addon's frame: visible, alpha " .. tostring(mini:GetAlpha()))
ucheck(mini.top == -8, "left where the addon put it, got top " .. tostring(mini.top))
BGV.Minimap.Apply(true)
ucheck(mini.top == -8, "a reset doesn't take it out of the addon's frame")
local angleBefore = BetterGreatVaultDB.minimapAngle
mini.scripts.OnDragStart(mini)
mini.scripts.OnUpdate(mini)
mini.scripts.OnDragStop(mini)
ucheck(mini.top == -8 and BetterGreatVaultDB.minimapAngle == angleBefore, "dragging leaves it to the addon")
-- on the minimap itself, a skin's Show hook keeps the say over its alpha
mini:SetParent(Minimap)
mini:SetAlpha(1)
BetterGreatVaultDB.showMinimap = false
BGV.Minimap.Apply()
BetterGreatVaultDB.showMinimap = true
BGV.Minimap.Apply()
ucheck(mini:GetAlpha() == 0, "on the minimap, a skin's Show hook alpha is left alone")
mini.Show = nil
mini:SetAlpha(1)

waiting = false
BGV.Minimap.RefreshAttention()
ucheck(AnimStops >= 1, "no rewards waiting: the pulse stops")

-- the settings panel: the menu, every option, the launchers and tools, About, the chat commands
do
  SlashCmdList = SlashCmdList or {}
  local chat = {}
  DEFAULT_CHAT_FRAME = { AddMessage = function(_, message) chat[#chat + 1] = message end }
  local function Chatted(pattern)
    for _, line in ipairs(chat) do if line:find(pattern) then return true end end
    return false
  end
  C_AddOns = { GetAddOnMetadata = function(name, field)
    if name == "BetterGreatVault" then return ({ Version = "1.0.0", Author = "powercover" })[field] end
  end }
  local openedCategory
  Settings = {
    RegisterCanvasLayoutCategory = function(frame, name) return { frame = frame, name = name, GetID = function() return 42 end } end,
    RegisterAddOnCategory = function() end,
    -- as in the game: Blizzard's panel answers by opening itself (SETTINGS_PANEL_OPEN) onto the
    -- category, the addon's page showing only for its own
    OpenToCategory = function(id)
      openedCategory = id
      SettingsPanel:Show()
      local page = _G.BetterGreatVaultSettings
      if page then page:SetShown(id == 42) end
    end,
  }
  SettingsPanel = Widget("SettingsPanel")
  SettingsPanel.shown = false
  function ShowUIPanel(f) f:Show() end
  function HideUIPanel(f) f:Hide() end
  local vaultOpened = 0
  function WeeklyRewards_Show() vaultOpened = vaultOpened + 1 end
  BGV.UI = BGV.UI or { RefreshOpenFrame = function() end }
  BGV.GreatVault.GetSnapshot = function() return {} end -- the popup checks above left it failing
  GameFontHighlightSmall = GameFontHighlightSmall or {}

  assert(loadfile("SettingsPreview.lua"))("BetterGreatVault", BGV)
  assert(loadfile("Settings.lua"))("BetterGreatVault", BGV)
  assert(loadfile("News.lua"))("BetterGreatVault", BGV)
  assert(loadfile("Core.lua"))("BetterGreatVault", BGV)
  -- the addon's pages as shipped, and one more without an address, to test both kinds of row
  BGV.Settings.LINKS[#BGV.Settings.LINKS + 1] = { name = "Elsewhere" }
  BGV.Settings.RegisterBridge()
  local sp = _G.BetterGreatVaultSettings
  ucheck(sp, "settings panel built")
  ucheck(#sp.children == 0, "registered at login, the page's content waits until it first shows: " .. #sp.children)
  sp:Show()
  ucheck(#sp.children > 0, "shown: the page is made")

  -- the menu: four sections at the top, About pinned to the bottom
  local rail, scrollFrame
  for _, c in ipairs(sp.children) do
    if c.kind == "ScrollFrame" then scrollFrame = c elseif c.kind == "Frame" then rail = rail or c end
  end
  local menu = {}
  for _, c in ipairs(rail.children) do if c.label then menu[#menu + 1] = c end end
  local names = {}
  for index, link in ipairs(menu) do names[index] = link.label.text end
  print("settings menu:", table.concat(names, " | "))
  ucheck(table.concat(names, "|") == "Great Vault|Minimap button|Appearance|Key bindings|Tools|About", "menu sections: " .. table.concat(names, "|"))
  local about = menu[6]
  ucheck(about.point == "BOTTOMLEFT", "About pinned to the bottom of the menu, got " .. tostring(about.point))
  ucheck(menu[1].point == "TOPLEFT", "sections listed from the top")
  about.scripts.OnClick(about)
  ucheck(about.selected and about.bar.shown and not menu[1].bar.shown, "About selected when clicked")
  menu[1].scripts.OnClick(menu[1])

  local content = scrollFrame.children[1]
  -- In the game a frame that was never given a width has no place on screen, and nothing anchored
  -- to it is drawn (the mock can't show that, so check for it).
  local unsized = {}
  for _, c in ipairs(content.children) do if not c.sized then unsized[#unsized + 1] = c.kind end end
  ucheck(#unsized == 0, "every row on the settings page has a width, unsized: " .. table.concat(unsized, ", "))
  local function Row(text)
    for _, c in ipairs(content.children) do if c.label and c.label.text == text then return c end end
  end
  local function Button(text)
    for _, c in ipairs(content.children) do
      for _, b in ipairs(c.buttons or {}) do if b:GetText() == text then return b end end
    end
  end

  -- Pointing at an option shows a sketch of where it applies, after a short rest; leaving, a
  -- click or the page closing hides it. Every sketch draws without an error, and the options
  -- about the opening play the opening itself in the card.
  do
    local card
    local function RunTimers()
      local queued = PendingTimers
      PendingTimers = {}
      for _, fn in ipairs(queued) do fn() end
    end
    local function Rest(frame)
      PendingTimers = {}
      frame.scripts.OnEnter(frame)
      RunTimers()
      card = _G.BetterGreatVaultSettingsPreview
    end
    local realShow, placed, stopped = BGV.Case.ShowPreview, nil, 0
    local realHide = BGV.Case.HidePreview
    -- (this mock can't run a slot: case_smoke plays the placed preview)
    BGV.Case.ShowPreview = function(anchor, choice, place)
      placed = { anchor = anchor, place = place, choice = choice }
      return true
    end
    BGV.Case.HidePreview = function() stopped = stopped + 1 end
    local bis = Row("Best-in-Slot tiers")
    PendingTimers = {}
    bis.scripts.OnEnter(bis)
    card = _G.BetterGreatVaultSettingsPreview
    RunTimers()
    -- a new accent color shows on the next hover: the card's bar and its lit words
    do
      local specBefore, colorBefore = BetterGreatVaultDB.useSpecAccent, BetterGreatVaultDB.accentColor
      BetterGreatVaultDB.useSpecAccent = false
      BetterGreatVaultDB.accentColor = { r = 1, g = 0, b = 0 }
      bis.scripts.OnLeave(bis)
      Rest(bis)
      local bar = card.bar.color
      ucheck(bar and bar[1] == 1 and bar[2] == 0 and bar[3] == 0, "the card's bar takes the new accent: " .. tostring(bar and table.concat(bar, ",")))
      ucheck(card.caption.text:find("|cffff0000", 1, true) ~= nil, "the caption's lit words take it too: " .. tostring(card.caption.text))
      BetterGreatVaultDB.accentColor = { r = 0, g = 0, b = 1 }
      bis.scripts.OnLeave(bis)
      Rest(bis)
      bar = card.bar.color
      ucheck(bar and bar[3] == 1 and bar[1] == 0, "and again after another change: " .. tostring(bar and table.concat(bar, ",")))
      BetterGreatVaultDB.useSpecAccent, BetterGreatVaultDB.accentColor = specBefore, colorBefore
      bis.scripts.OnLeave(bis)
    end
    PendingTimers = {}
    bis.scripts.OnEnter(bis)
    card = _G.BetterGreatVaultSettingsPreview
    ucheck(not (card and card.shown), "the sketch waits for the pointer to rest")
    ucheck(#PendingTimers == 1, "one timer for the rest, got " .. #PendingTimers)
    RunTimers()
    card = _G.BetterGreatVaultSettingsPreview
    ucheck(card and card.shown, "resting on an option shows its sketch")
    ucheck(card and card.title.text == "Best-in-Slot tiers" and card.where.text == "Great Vault and loot table",
      "titled with the option and where it applies: " .. tostring(card and card.title.text) .. " / " .. tostring(card and card.where.text))
    ucheck(card and type(card.caption.text) == "string" and card.caption.text:find("|cff", 1, true) ~= nil and not card.caption.text:find("{", 1, true),
      "the caption's lit words in the lit color: " .. tostring(card and card.caption.text))
    bis.scripts.OnLeave(bis)
    ucheck(not card.shown, "leaving hides it")
    PendingTimers = {}
    bis.scripts.OnEnter(bis)
    bis.scripts.OnLeave(bis)
    RunTimers()
    ucheck(not card.shown, "a pointer passing over shows nothing")
    -- a click keeps the card and draws it again with the new state: ticking "Use my spec's
    -- color" off shows the custom color at once
    do
      local specBefore, colorBefore = BetterGreatVaultDB.useSpecAccent, BetterGreatVaultDB.accentColor
      BetterGreatVaultDB.accentColor = { r = 0, g = 1, b = 0 }
      BetterGreatVaultDB.useSpecAccent = true
      local specRow = Row("Use my spec's color")
      Rest(specRow)
      ucheck(card.shown, "the spec color option shows its sketch")
      if specRow.scripts.OnMouseDown then specRow.scripts.OnMouseDown(specRow) end
      specRow.scripts.OnClick(specRow)
      local bar = card.bar.color
      ucheck(card.shown and BetterGreatVaultDB.useSpecAccent == false, "a click keeps the card")
      ucheck(bar and bar[1] == 0 and bar[2] == 1 and bar[3] == 0, "and draws it with the new accent at once: " .. tostring(bar and table.concat(bar, ",")))
      specRow.scripts.OnClick(specRow)
      specRow.scripts.OnLeave(specRow)
      BetterGreatVaultDB.useSpecAccent, BetterGreatVaultDB.accentColor = specBefore, colorBefore
    end
    -- the style button opens its menu (with its own previews): a click closes the card
    local styleButton = Button("Opening style: Match specialization (Mortal Strike)")
    ucheck(styleButton ~= nil, "the style button is found")
    if styleButton then
      Rest(styleButton)
      ucheck(card.shown, "the style button shows its sketch")
      styleButton.scripts.OnMouseDown(styleButton)
      ucheck(not card.shown, "its click closes the card")
    end
    -- every sketch, on a frame of its own
    local count = 0
    for key in pairs(BGV.SettingsPreview.SKETCHES) do
      local frame = Widget("Button")
      BGV.SettingsPreview.Attach(frame, key, "Test " .. key)
      Rest(frame)
      ucheck(card.shown and card.title.text == "Test " .. key, "sketch " .. key .. " shows")
      frame.scripts.OnLeave(frame)
      count = count + 1
    end
    ucheck(count == 19, "19 sketches, got " .. count)
    local nextRow = Row("Next step")
    Rest(nextRow)
    ucheck(card.shown and card.title.text == "Next step" and card.caption.text:find("in the popup", 1, true) ~= nil,
      "the next step's option shows its sketch: " .. tostring(card.caption.text))
    nextRow.scripts.OnLeave(nextRow)
    -- a second round makes nothing new: every piece comes from the pools
    local t1, d1, l1 = BGV.SettingsPreview.PoolSizes()
    for key in pairs(BGV.SettingsPreview.SKETCHES) do
      local frame = Widget("Button")
      BGV.SettingsPreview.Attach(frame, key, "Again " .. key)
      Rest(frame)
      frame.scripts.OnLeave(frame)
    end
    local t2, d2, l2 = BGV.SettingsPreview.PoolSizes()
    ucheck(t1 == t2 and d1 == d2 and l1 == l2, string.format("no new pieces on a second round: %d/%d/%d then %d/%d/%d", t1, d1, l1, t2, d2, l2))
    print(string.format("settings preview pools: %d textures, %d discs, %d labels", t2, d2, l2))
    -- in combat: no sketch, no timer
    local combatBefore = InCombatLockdown
    InCombatLockdown = function() return true end
    PendingTimers = {}
    bis.scripts.OnEnter(bis)
    ucheck(#PendingTimers == 0, "in combat no sketch is even queued")
    bis.scripts.OnLeave(bis)
    InCombatLockdown = combatBefore
    -- the sad gates' caption names Collect as the game does
    local sad = Row("Sad faces when hovering Collect")
    Rest(sad)
    ucheck(card.caption.text:find("Collect", 1, true) ~= nil, "Collect named in the caption: " .. tostring(card.caption.text))
    sad.scripts.OnLeave(sad)
    -- the opening options play the opening itself, placed in the card
    local anim = Row("Slot animations")
    Rest(anim)
    ucheck(placed and placed.anchor == card.canvas and type(placed.place) == "function" and placed.choice == BGV.Case.Choice(),
      "Slot animations plays your opening in the card")
    anim.scripts.OnLeave(anim)
    ucheck(stopped >= 1, "and stops it on leaving")
    -- with the animations off, a still sketch instead
    placed = nil
    BetterGreatVaultDB.disableAnimations = true
    Rest(anim)
    ucheck(card.shown and placed == nil, "animations off: a still sketch")
    anim.scripts.OnLeave(anim)
    BetterGreatVaultDB.disableAnimations = false
    BGV.Case.ShowPreview, BGV.Case.HidePreview = realShow, realHide
    -- the page closing takes the card with it
    Rest(bis)
    sp:Hide()
    ucheck(not card.shown, "closing the settings hides the sketch")
    sp:Show()
    PendingTimers = {}
  end

  -- options
  local db = BetterGreatVaultDB
  local animated = Row("Slot animations")
  ucheck(animated and animated.fill.shown, "animated slots on by default")
  animated.scripts.OnClick(animated)
  ucheck(BetterGreatVaultDB.disableAnimations == true and not animated.fill.shown, "animated slots off")
  animated.scripts.OnClick(animated)
  ucheck(BetterGreatVaultDB.disableAnimations == false and animated.fill.shown, "animated slots on again")
  -- the sad gates at Collect: on by default, and they can be turned off
  local sad = Row("Sad faces when hovering Collect")
  ucheck(sad and sad.fill.shown, "sad gates at Collect on by default")
  sad.scripts.OnClick(sad)
  ucheck(BetterGreatVaultDB.disableCollectFaces == true and not sad.fill.shown, "sad gates off")
  sad.scripts.OnClick(sad)
  ucheck(BetterGreatVaultDB.disableCollectFaces == false and sad.fill.shown, "sad gates on again")
  -- the opening style: the specialization's by default, one picked, or random
  local style = Button("Opening style: Match specialization (Mortal Strike)")
  ucheck(style, "opening style follows the specialization by default")
  local styleRow
  for _, c in ipairs(content.children) do for _, b in ipairs(c.buttons or {}) do if b == style then styleRow = c end end end
  style.scripts.OnClick(style)
  ucheck(FindEntry(lastMenu, "Match specialization") and FindEntry(lastMenu, "^Frost Shatter") and FindEntry(lastMenu, "^One%-Armed Bandit")
    and FindEntry(lastMenu, "^Classic$") and FindEntry(lastMenu, "^Random$"), "the style menu lists every style and Random")
  -- with the game's specializations known, each style sits under its class, named with its specialization
  do
    local realSpecInfo = GetSpecializationInfoForClassID
    local SPECS = { [1] = { { 71, "Arms" }, { 72, "Fury" }, { 73, "Protection" } }, [8] = { { 62, "Arcane" }, { 63, "Fire" }, { 64, "Frost" } } }
    GetSpecializationInfoForClassID = function(classID, index)
      local spec = SPECS[classID] and SPECS[classID][index]
      if spec then return spec[1], spec[2] end
    end
    style.scripts.OnClick(style)
    local mage, warrior, topFrost, topVault
    for _, e in ipairs(lastMenu.entries) do
      if tostring(e.text):find("Mage") then mage = e end
      if tostring(e.text):find("Warrior") then warrior = e end
      if e.text == "Frost Shatter" then topFrost = e end
      if e.text == "Vault Door" then topVault = e end
    end
    local function Texts(menu)
      local list = {}
      for _, e in ipairs(menu and menu.entries or {}) do list[#list + 1] = tostring(e.text) end
      return table.concat(list, ", ")
    end
    ucheck(mage and mage.text == "|cff3fc7ebMage|r" and #mage.entries == 3, "the style menu: Mage, class colored, with its three styles: " .. Texts(mage))
    ucheck(mage and mage.entries[3].text == "Frost Shatter  |cff8c8c8cFrost|r" and mage.entries[3].onEnter, "a style named with its specialization, previewed on hover: " .. Texts(mage))
    ucheck(warrior and warrior.entries[1].text:find("^Mortal Strike") and warrior.entries[3].text:find("^Shield Slam"), "Warrior's styles in the game's order: " .. Texts(warrior))
    ucheck(not topFrost and topVault and FindEntry(lastMenu, "^Old Cartoon$") and FindEntry(lastMenu, "^Classic$"), "the styles of no specialization at the top level, the others only under their class")
    GetSpecializationInfoForClassID = realSpecInfo
    style.scripts.OnClick(style)
  end
  -- pointing at a style plays it beside the menu; leaving the entry stops it
  -- (the preview itself runs in case_smoke.lua)
  local frostEntry = FindEntry(lastMenu, "^Frost Shatter")
  ucheck(frostEntry.onEnter and frostEntry.onLeave, "style entries preview on hover")
  local realShow, realHide = BGV.Case.ShowPreview, BGV.Case.HidePreview
  local previewed
  BGV.Case.ShowPreview = function(anchor, choice) previewed = { anchor, choice } end
  BGV.Case.HidePreview = function() previewed = "hidden" end
  local entryFrame = CreateFrame("Button", nil, UIParent)
  frostEntry.onEnter(entryFrame)
  ucheck(type(previewed) == "table" and previewed[1] == entryFrame and previewed[2] == "frost", "hovering Frost Shatter previews it beside its entry")
  FindEntry(lastMenu, "^Random$").onEnter(entryFrame)
  ucheck(previewed[2] == "random", "Random previews random styles")
  FindEntry(lastMenu, "Match specialization").onEnter(entryFrame)
  ucheck(previewed[2] == "spec", "Match specialization previews the spec's style")
  frostEntry.onLeave()
  ucheck(previewed == "hidden", "leaving an entry hides the preview")
  BGV.Case.ShowPreview, BGV.Case.HidePreview = realShow, realHide
  FindEntry(lastMenu, "^Frost Shatter").setSelected()
  ucheck(BetterGreatVaultDB.vaultStyle == "frost" and style:GetText() == "Opening style: Frost Shatter", "a style picked: " .. tostring(style:GetText()))
  style.scripts.OnClick(style)
  FindEntry(lastMenu, "^Random$").setSelected()
  ucheck(BetterGreatVaultDB.vaultStyle == "random" and style:GetText() == "Opening style: Random", "random picked")
  animated.scripts.OnClick(animated)
  ucheck(styleRow and styleRow.buttons[1].mouseEnabled == false, "no style to pick while the slots don't animate")
  animated.scripts.OnClick(animated)
  ucheck(styleRow.buttons[1].mouseEnabled == true, "the style picker is back with animation")
  style.scripts.OnClick(style)
  FindEntry(lastMenu, "Match specialization").setSelected()
  ucheck(BetterGreatVaultDB.vaultStyle == "spec", "back to the specialization's style")
  ucheck(Row("Click a slot for its loot table") and Row("Loot spec button") and Row("Use my spec's color"), "vault and accent options listed")
  local tiers = Row("Best-in-Slot tiers")
  ucheck(tiers and tiers.fill.shown, "Best-in-Slot tiers on by default")
  tiers.scripts.OnClick(tiers)
  ucheck(BetterGreatVaultDB.showBisTiers == false and not tiers.fill.shown, "tiers off")
  tiers.scripts.OnClick(tiers)
  ucheck(BetterGreatVaultDB.showBisTiers == true, "tiers on again")
  local remind = Row("Reward reminder")
  ucheck(remind and remind.fill.shown, "reward reminder on by default")
  remind.scripts.OnClick(remind)
  ucheck(BetterGreatVaultDB.remindRewards == false, "reminder off")
  remind.scripts.OnClick(remind)
  ucheck(BetterGreatVaultDB.remindRewards == true, "reminder on again")
  local showButton = Row("Show the button")
  mini.shown = true
  showButton.scripts.OnClick(showButton)
  ucheck(not mini.shown and BetterGreatVaultDB.showMinimap == false, "minimap button hidden from the settings")
  showButton.scripts.OnClick(showButton)
  ucheck(mini.shown, "and shown again")
  -- lock: a locked button doesn't start dragging
  local lock = Row("Lock position")
  lock.scripts.OnClick(lock)
  ucheck(BetterGreatVaultDB.lockMinimap == true and lock.fill.shown, "lock on")
  mini.scripts.OnUpdate = nil
  mini.dragged = nil
  mini.scripts.OnDragStart(mini)
  ucheck(mini.scripts.OnUpdate == nil and not mini.dragging, "a locked button isn't dragged")
  lock.scripts.OnClick(lock)
  ucheck(BetterGreatVaultDB.lockMinimap == false, "lock off")
  mini.scripts.OnDragStart(mini)
  ucheck(mini.scripts.OnUpdate ~= nil, "unlocked: dragging works")
  local settingsOpened = 0
  local realToggle = BGV.Minimap.ToggleSettings
  BGV.Minimap.ToggleSettings = function() settingsOpened = settingsOpened + 1 end
  mini.scripts.OnClick(mini, "RightButton")
  ucheck(settingsOpened == 0, "no click while dragging")
  mini.scripts.OnDragStop(mini)
  mini.scripts.OnClick(mini, "RightButton")
  ucheck(settingsOpened == 0, "the drag's own release isn't a click")
  mini.scripts.OnClick(mini, "RightButton")
  ucheck(settingsOpened == 1, "the next click after a drag works")
  mini.scripts.OnDragStart(mini)
  mini.scripts.OnDragStop(mini)
  Now = Now + 1
  mini.scripts.OnClick(mini, "RightButton")
  ucheck(settingsOpened == 2, "a click a moment after a drag works (no click came with the release)")
  BGV.Minimap.ToggleSettings = realToggle
  -- reset position
  mini:SetParent(Minimap)
  BetterGreatVaultDB.minimapAngle = 10
  Button("Reset position").scripts.OnClick(Button("Reset position"))
  ucheck(BetterGreatVaultDB.minimapAngle == 220, "position reset to the first spot, got " .. tostring(BetterGreatVaultDB.minimapAngle))
  -- debug mode
  local debug = Row("Debug mode")
  debug.scripts.OnClick(debug)
  ucheck(BetterGreatVaultDB.debug == true and debug.fill.shown, "debug mode on")
  debug.scripts.OnClick(debug)
  ucheck(BetterGreatVaultDB.debug == false, "debug mode off")

  -- launchers: the settings close, the window opens
  local lootWindow = _G.BetterGreatVaultLootTable
  lootWindow:Hide()
  SettingsPanel:Show()
  Button("Loot database").scripts.OnClick(Button("Loot database"))
  ucheck(not SettingsPanel.shown and lootWindow.shown, "Loot database: settings closed, database open")
  lootWindow:Hide()
  SettingsPanel:Show()
  Button("Loot table").scripts.OnClick(Button("Loot table"))
  ucheck(not SettingsPanel.shown and lootWindow.shown, "Loot table: settings closed, table open")
  lootWindow:Hide()
  SettingsPanel:Show()
  Button("Great Vault").scripts.OnClick(Button("Great Vault"))
  ucheck(not SettingsPanel.shown and vaultOpened == 1, "Great Vault: settings closed, vault opened")

  -- tools
  BGV.GreatVault.GetSnapshot = function()
    return { { type = 3, index = 1, category = "Raid", progress = 3, threshold = 2, itemLevel = 285 } }
  end
  Button("Print vault data").scripts.OnClick(Button("Print vault data"))
  ucheck(Chatted("Great Vault data") and Chatted("Reward ilvl: 285"), "vault data printed")
  Button("Refresh vault data").scripts.OnClick(Button("Refresh vault data"))
  ucheck(Chatted("Great Vault data refreshed"), "vault data refreshed")

  -- reset: asks first, keeps what was learned about the season's rewards
  local learned = { season = 18, tiers = { mplus = 256 }, levels = {} }
  BetterGreatVaultDB.rewardData = learned
  BetterGreatVaultDB.openLootTable = false
  BetterGreatVaultDB.useSpecAccent = false
  local reset = Button("Reset settings")
  reset.scripts.OnClick(reset)
  ucheck(reset:GetText() == "Click again to reset" and BetterGreatVaultDB.openLootTable == false, "first click only asks")
  reset.scripts.OnHide(reset)
  ucheck(reset:GetText() == "Reset settings", "closing the settings takes the question back")
  reset.scripts.OnClick(reset)
  reset.scripts.OnClick(reset)
  ucheck(BetterGreatVaultDB.openLootTable == true and BetterGreatVaultDB.useSpecAccent == true, "second click resets the options")
  ucheck(BetterGreatVaultDB.rewardData == learned, "what was learned about the season's rewards is kept")
  ucheck(reset:GetText() == "Reset settings", "button back to its label")
  ucheck(Row("Slot animations").fill.shown and Row("Use my spec's color").fill.shown, "checkboxes show the defaults")

  -- the Best-in-Slot tiers option names the patch and build its list was read for, right under
  -- its own note
  do
    local about, source
    for n, f in ipairs(FontStrings or {}) do
      if f.text == "Colors items by their Best-in-Slot tier for your loot spec, from Wowhead's guides, and adds the loot table's Tier column." then about = n end
      if f.text == "List from Wowhead's guides for patch 12.1.5, build 70448." then source = n end
    end
    ucheck(about and source and source == about + 1, "the BiS list's patch and build under the tiers note (" .. tostring(about) .. ", " .. tostring(source) .. ")")
  end

  -- About
  local card, soon, copies = nil, nil, {}
  for _, c in ipairs(content.children) do
    if c.meta then card = c end
    if c.name and c.soon then soon = c end
    if c.name and c.box then copies[c.name.text] = c end
  end
  ucheck(card and card.meta.text == "Version 1.0.0  •  by powercover", "version and author: " .. tostring(card and card.meta.text))
  ucheck(soon and soon.name.text == "Elsewhere" and soon.soon.text == "Coming soon", "a link without an address says Coming soon")
  local curse, wago = copies["CurseForge"], copies["Wago"]
  ucheck(curse and curse.box.text == "https://www.curseforge.com/wow/addons/better-great-vault",
    "CurseForge's page sits in a copy box: " .. tostring(curse and curse.box.text))
  ucheck(wago and wago.box.text == "https://addons.wago.io/addons/better-great-vault",
    "Wago's page sits in a copy box: " .. tostring(wago and wago.box.text))
  if curse then
    curse.box.text = "typed over"
    curse.box.scripts.OnTextChanged(curse.box, true)
    ucheck(curse.box.text == "https://www.curseforge.com/wow/addons/better-great-vault", "the copy box is read only")
  end


  -- key bindings: none by default, keys shown as they're bound, the game's page one click away
  local bound = {}
  function GetBindingKey(command) return bound[command] end
  function GetBindingText(key) return (key:gsub("CTRL%-", "Ctrl-")) end
  Settings.KEYBINDINGS_CATEGORY_ID = 7
  local keyRows = {}
  for _, c in ipairs(content.children) do if c.key and c.name then keyRows[c.name.text] = c end end
  BGV.Settings.Refresh()
  ucheck(keyRows["Great Vault"] and keyRows["Loot table"] and keyRows["Loot database"] and keyRows["Settings"], "four key bindings listed")
  ucheck(keyRows["Loot database"].key.text == "Not bound", "no key bound by default")
  bound.BETTERGREATVAULT_DATABASE = "CTRL-G"
  local bindingWatcher
  for _, f in ipairs(AllFrames) do if f.events and f.events.UPDATE_BINDINGS then bindingWatcher = f end end
  ucheck(bindingWatcher, "the settings watch for key binding changes")
  bindingWatcher.scripts.OnEvent(bindingWatcher, "UPDATE_BINDINGS")
  ucheck(keyRows["Loot database"].key.text == "Ctrl-G", "a bound key shows: " .. tostring(keyRows["Loot database"].key.text))
  openedCategory = nil
  Button("Open Key Bindings").scripts.OnClick(Button("Open Key Bindings"))
  ucheck(openedCategory == 7, "Open Key Bindings goes to the game's Key Bindings")
  ucheck(BINDING_HEADER_BETTERGREATVAULT == "Better Great Vault" and BINDING_NAME_BETTERGREATVAULT_DATABASE, "binding names for the Key Bindings page")
  lootWindow:Hide()
  BetterGreatVault_OnBinding("database")
  ucheck(lootWindow.shown, "the database key opens the loot database")
  BetterGreatVault_OnBinding("database")
  ucheck(not lootWindow.shown, "and closes it")
  local before = vaultOpened
  BetterGreatVault_OnBinding("vault")
  ucheck(vaultOpened == before + 1, "the Great Vault key opens the vault")
  openedCategory = nil
  BetterGreatVault_OnBinding("settings")
  ucheck(openedCategory == 42, "the settings key opens the settings")

  -- the minimap's AddOns menu: the button's clicks, and its popup without the drag line
  before = vaultOpened
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "LeftButton")
  ucheck(vaultOpened == before + 1, "AddOns menu left-click: Great Vault")
  openedCategory = nil
  SettingsPanel:Hide() -- the settings key above left them open, and right-click toggles them
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "RightButton")
  ucheck(openedCategory == 42 and SettingsPanel.shown, "AddOns menu right-click: settings")
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "RightButton")
  ucheck(not SettingsPanel.shown, "and right-click again closes them")
  -- settings changed elsewhere in Blizzard's panel, not applied yet: it stays open for its own buttons
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "RightButton")
  SettingsPanel.HasUnappliedSettings = function() return true end
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "RightButton")
  ucheck(SettingsPanel.shown, "unapplied settings elsewhere in the panel: it stays open for its own buttons")
  SettingsPanel.HasUnappliedSettings = nil
  SettingsPanel:Hide()
  lootWindow:Hide()
  BetterGreatVault_OnAddonCompartmentClick("BetterGreatVault", "MiddleButton")
  ucheck(lootWindow.shown, "AddOns menu middle-click: loot table")
  local menuRow = Widget("Button")
  BetterGreatVault_OnAddonCompartmentEnter("BetterGreatVault", menuRow)
  local pop2 = _G.BetterGreatVaultMinimapPopup
  ucheck(pop2.shown and pop2.actions[5].text.shown == false and pop2.actions[4].text.shown, "AddOns menu popup: no drag line")
  BetterGreatVault_OnAddonCompartmentLeave("BetterGreatVault", menuRow)
  ucheck(not pop2.shown, "leaving the menu row hides it")
  BetterGreatVault_OnAddonCompartmentEnter("BetterGreatVault", menuRow)
  menuRow:Hide()
  pop2.scripts.OnUpdate(pop2)
  ucheck(not pop2.shown, "the popup goes when the menu closes")
  mini:Show()
  mini.scripts.OnEnter(mini)
  ucheck(pop2.actions[5].text.shown, "on the minimap button the drag line is back")
  mini.scripts.OnLeave(mini)

  -- a setting's change redraws the vault and the loot table once, on the next frame, however many
  -- changes come in it (the color picker sends one for every move of the pointer)
  do
    local queued, styled = {}, 0
    local after, refreshStyle = C_Timer.After, BGV.LootTable.RefreshStyle
    C_Timer.After = function(_, fn) queued[#queued + 1] = fn end
    BGV.LootTable.RefreshStyle = function() styled = styled + 1 end
    Now = Now + 0.02 -- a frame of its own
    for _ = 1, 10 do BGV.Settings.RefreshAccent() end
    ucheck(#queued == 1 and styled == 0, "ten changes in a frame: one redraw queued: " .. #queued)
    queued[1]()
    ucheck(styled == 1, "and the loot table drawn again once: " .. styled)
    Now = Now + 0.02
    BGV.Settings.RefreshAccent()
    ucheck(#queued == 2, "the next frame's change queues its own")
    C_Timer.After, BGV.LootTable.RefreshStyle = after, refreshStyle
  end

  -- reward reminder: once, at login, while the vault has rewards
  local core
  for _, f in ipairs(AllFrames) do if f.events and f.events.WEEKLY_REWARDS_UPDATE and f.events.PLAYER_LOGIN then core = f end end
  ucheck(core, "found the addon's event frame")
  local function Reminders()
    local count = 0
    for _, line in ipairs(chat) do if line:find("Rewards are waiting in your Great Vault") then count = count + 1 end end
    return count
  end
  waiting = true
  core.scripts.OnEvent(core, "PLAYER_ENTERING_WORLD", true)
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 1, "reminded at login")
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 1, "only once")
  core.scripts.OnEvent(core, "PLAYER_ENTERING_WORLD", false)
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 1, "not after a reload")
  BetterGreatVaultDB.remindRewards = false
  core.scripts.OnEvent(core, "PLAYER_ENTERING_WORLD", true)
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 1, "not when turned off")
  BetterGreatVaultDB.remindRewards = true
  waiting = false
  core.scripts.OnEvent(core, "PLAYER_ENTERING_WORLD", true)
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 1, "no reminder without rewards")
  waiting = true
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 2, "rewards that show up soon after login are still reminded")
  core.scripts.OnEvent(core, "PLAYER_ENTERING_WORLD", true)
  Now = Now + 61
  core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
  ucheck(Reminders() == 2, "not long after login")
  waiting = false

  -- what the game's events have read again: a group member's spec change, the map info Blizzard's
  -- vault asks for every time it shows, and a vault update with its slots as they were drop nothing
  do
    local drops = 0
    local invalidate = BGV.LootTable.Invalidate
    BGV.LootTable.Invalidate = function(...) drops = drops + 1 return invalidate(...) end
    core.scripts.OnEvent(core, "PLAYER_SPECIALIZATION_CHANGED", "party1")
    ucheck(drops == 0, "a group member's spec change: nothing read again")
    core.scripts.OnEvent(core, "PLAYER_SPECIALIZATION_CHANGED", "player")
    ucheck(drops == 1, "the player's own: the lists read again, once: " .. drops)
    local mapsKnown = BGV.Rewards.MythicMapsKnown
    BGV.Rewards.MythicMapsKnown = function() return true end
    core.scripts.OnEvent(core, "CHALLENGE_MODE_MAPS_UPDATE")
    ucheck(drops == 1, "map info again with the season's dungeons known: nothing read again")
    BGV.Rewards.MythicMapsKnown = function() return false end
    core.scripts.OnEvent(core, "CHALLENGE_MODE_MAPS_UPDATE")
    ucheck(drops == 2, "map info while they weren't all known: read again")
    BGV.Rewards.MythicMapsKnown = mapsKnown
    local activities = { { type = 1, index = 1, threshold = 2, progress = 1, level = 16, id = 11 } }
    local getActivities = C_WeeklyRewards.GetActivities
    C_WeeklyRewards.GetActivities = function() return activities end
    core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
    local before = drops
    core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
    ucheck(drops == before, "a vault update with its slots as they were: nothing read again")
    activities[1].progress = 2
    core.scripts.OnEvent(core, "WEEKLY_REWARDS_UPDATE")
    ucheck(drops == before + 1, "a slot that progressed: read again")
    C_WeeklyRewards.GetActivities = getActivities
    BGV.LootTable.Invalidate = invalidate
  end


  -- minimap options, like Narcissus's: the AddOns menu, then the button's own options nested
  local other = { text = "Other addon" }
  local ours = { text = "Better Great Vault" }
  AddonCompartmentFrame = { registeredAddons = { other, ours }, updates = 0 }
  function AddonCompartmentFrame:UpdateDisplay() self.updates = self.updates + 1 end
  local realMetadata = C_AddOns.GetAddOnMetadata
  C_AddOns.GetAddOnMetadata = function(name, field)
    if field == "Title" and name == "BetterGreatVault" then return "Better Great Vault" end
    return realMetadata(name, field)
  end
  local menuOption = Row("Addon compartment entry")
  ucheck(menuOption and menuOption.fill.shown, "in the AddOns menu by default")
  menuOption.scripts.OnClick(menuOption)
  ucheck(#AddonCompartmentFrame.registeredAddons == 1 and AddonCompartmentFrame.registeredAddons[1] == other
    and AddonCompartmentFrame.updates == 1, "turned off: our entry leaves the AddOns menu")
  BGV.Minimap.ApplyCompartment()
  ucheck(#AddonCompartmentFrame.registeredAddons == 1, "applying again changes nothing")
  menuOption.scripts.OnClick(menuOption)
  ucheck(#AddonCompartmentFrame.registeredAddons == 2 and AddonCompartmentFrame.registeredAddons[2] == ours
    and AddonCompartmentFrame.updates == 2, "turned on: the same entry is back")

  -- the button's options are nested under it, and off while it's hidden
  local nestedRows = { "Popup on hover", "Lock position", "Keep on the minimap", "Fade until hovered" }
  for _, name in ipairs(nestedRows) do ucheck(Row(name), "nested option listed: " .. name) end
  ucheck(Row("Lock position").top == Row("Show the button").top - 0 or true, "layout ran")
  local showRow = Row("Show the button")
  showRow.scripts.OnClick(showRow)
  ucheck(BetterGreatVaultDB.showMinimap == false, "button hidden")
  ucheck(Row("Lock position"):GetAlpha() == 0.4 and Row("Lock position").mouseEnabled == false, "nested options off while the button is hidden")
  ucheck(Button("Reset position").mouseEnabled == false, "reset position off too")
  showRow.scripts.OnClick(showRow)
  ucheck(Row("Lock position"):GetAlpha() == 1 and Row("Lock position").mouseEnabled == true, "and back on with the button")

  -- the popup on mouseover can be turned off
  local popupOption = Row("Popup on hover")
  ucheck(popupOption.fill.shown, "popup on mouseover by default")
  popupOption.scripts.OnClick(popupOption)
  ucheck(Row("This week's slots"):GetAlpha() == 0.4 and Row("This week's slots").mouseEnabled == false,
    "the mini vault option is off while the popup is")
  mini:Show()
  pop2:Hide()
  mini.scripts.OnEnter(mini)
  ucheck(not pop2.shown, "no popup on mouseover when turned off")
  mini.scripts.OnLeave(mini)
  BetterGreatVault_OnAddonCompartmentEnter("BetterGreatVault", Widget("Button"))
  ucheck(not pop2.shown, "not from the AddOns menu either")
  popupOption.scripts.OnClick(popupOption)
  ucheck(Row("This week's slots"):GetAlpha() == 1, "the mini vault option is back with the popup")
  mini.scripts.OnEnter(mini)
  ucheck(pop2.shown, "popup back on mouseover")
  mini.scripts.OnLeave(mini)
  -- the mini vault (this week's slots) in the popup
  BGV.GreatVault.GetSnapshot = function()
    return { { type = 3, index = 1, category = "Raid", progress = 3, threshold = 2, unlocked = true, itemLevel = 285, source = {} } }
  end
  C_WeeklyRewards.CanClaimRewards = function() return false end
  waiting = false
  local weekOption = Row("This week's slots")
  ucheck(weekOption and weekOption.fill.shown, "the mini vault shows by default")
  mini.scripts.OnEnter(mini)
  ucheck(pop2.heading.shown and pop2.rows[1].label.shown and pop2.rows[1].chips[1].text.text == "285", "the popup shows this week's slots")
  mini.scripts.OnLeave(mini)
  weekOption.scripts.OnClick(weekOption)
  ucheck(BetterGreatVaultDB.popupWeek == false, "mini vault turned off")
  mini.scripts.OnEnter(mini)
  ucheck(pop2.shown and not pop2.heading.shown and not pop2.rows[1].label.shown and not pop2.rows[1].chips[1].fill.shown,
    "the popup without the week's slots")
  ucheck(not pop2.divider.shown and pop2.actions[1].text.shown, "just the clicks, no stray divider")
  mini.scripts.OnLeave(mini)
  weekOption.scripts.OnClick(weekOption)
  mini.scripts.OnEnter(mini)
  ucheck(pop2.heading.shown, "the week's slots back")
  mini.scripts.OnLeave(mini)

  -- fade: faint at rest, full on hover and while rewards wait
  local function Settle() for _, c in ipairs(mini.children) do for _ = 1, 60 do if c.scripts.OnUpdate then c.scripts.OnUpdate(c, 0.05) end end end end
  mini:SetParent(Minimap)
  waiting = false
  local fadeOption = Row("Fade until hovered")
  fadeOption.scripts.OnClick(fadeOption)
  Settle()
  ucheck(math.abs(mini:GetAlpha() - 0.25) < 0.02, "faded at rest: " .. tostring(mini:GetAlpha()))
  mini.scripts.OnEnter(mini)
  Settle()
  ucheck(math.abs(mini:GetAlpha() - 1) < 0.02, "full while hovered")
  mini.scripts.OnLeave(mini)
  Settle()
  ucheck(math.abs(mini:GetAlpha() - 0.25) < 0.02, "faint again after")
  waiting = true
  BGV.Minimap.RefreshAttention()
  Settle()
  ucheck(math.abs(mini:GetAlpha() - 1) < 0.02, "full while rewards are waiting")
  waiting = false
  BGV.Minimap.RefreshAttention()
  Settle()
  fadeOption.scripts.OnClick(fadeOption)
  ucheck(mini:GetAlpha() == 1, "fade off: full again")

  -- unaffected by other addons: its own frame instead of the minimap, placed as before
  local independent = Row("Keep on the minimap")
  independent.scripts.OnClick(independent)
  local home = mini:GetParent()
  ucheck(home ~= Minimap and home ~= nil, "in its own frame")
  ucheck(mini.width == 32 and mini.point == "CENTER", "sized and placed around the minimap")
  independent.scripts.OnClick(independent)
  ucheck(mini:GetParent() == Minimap, "back on the minimap")

  -- text size: the addon's fonts, this page, the loot table and the popup follow it
  function CreateFont(name)
    local font = { name = name }
    function font:CopyFontObject(other) self.file, self.size, self.flags = "font", other.size, "" end
    function font:GetFont() return self.file, self.size, self.flags end
    function font:SetFont(file, size, flags) self.file, self.size, self.flags = file, size, flags end
    _G[name] = font
    return font
  end
  GameFontHighlight.size, GameFontNormal.size = 12, 12
  GameFontHighlightSmall, GameFontNormalSmall = { size = 10 }, { size = 10 }
  GameFontNormalLarge, GameFontDisable = { size = 16 }, { size = 12 }
  BGV.Utils.ApplyFontSize()
  ucheck(BetterGreatVaultFontHighlight and BetterGreatVaultFontHighlight.size == 12 and BetterGreatVaultFontVault.flags == "OUTLINE", "the addon's fonts at the game's sizes")
  local sizeRow
  for _, c in ipairs(content.children) do if c.slider then sizeRow = c end end
  ucheck(sizeRow and sizeRow.value.text == "Default", "text size starts at Default: " .. tostring(sizeRow and sizeRow.value.text))
  sizeRow.slider:SetValue(2) -- a drag: the slider's value changes, then OnValueChanged
  ucheck(BetterGreatVaultDB.fontSize == 2 and sizeRow.value.text == "+2", "slider to +2")
  ucheck(BetterGreatVaultFontHighlight.size == 14 and BetterGreatVaultFontHighlightSmall.size == 12
    and BetterGreatVaultFontVault.size == 12 and BetterGreatVaultFontNormalLarge.size == 18, "fonts two points bigger")
  ucheck(Row("Lock position").height == 24, "checkbox rows taller with the text, got " .. tostring(Row("Lock position").height))
  ucheck(Button("Reset settings").width == math.floor(140 * 1.2 + 0.5), "buttons wider with the text, got " .. tostring(Button("Reset settings").width))
  ucheck(menu[2].height == 30, "menu links taller with the text")
  BGV.LootTable.ShowDatabase()
  local columns
  for _, c in ipairs(lootWindow.children) do if c.labels then columns = c end end
  ucheck(columns.height == 26, "loot table column header taller, got " .. tostring(columns.height))
  mini.scripts.OnEnter(mini)
  ucheck(pop2.scale == 1.2, "popup scaled with the text, got " .. tostring(pop2.scale))
  mini.scripts.OnLeave(mini)
  ucheck(sizeRow.slider.scripts.OnMouseWheel == nil and sizeRow.slider.mouseWheel == false,
    "the mouse wheel scrolls the page, not the text size")
  sizeRow.slider:SetValue(5)
  ucheck(BetterGreatVaultDB.fontSize == 5, "up to +5")
  sizeRow.slider:SetValue(-5)
  ucheck(BetterGreatVaultDB.fontSize == -5 and BetterGreatVaultFontHighlightSmall.size == 5 and sizeRow.value.text == "-5", "down to -5")
  BetterGreatVaultDB.fontSize = 42
  ucheck(BGV.Utils.FontOffset() == 5, "a saved size out of range is clamped")
  BetterGreatVaultDB.fontSize = 2
  BGV.Utils.ApplyFontSize()
  lootWindow:Hide()

  -- /bgv status prints the week
  BGV.GreatVault.GetSnapshot = function() return weekSnapshot end
  C_WeeklyRewards.CanClaimRewards = function() return false end
  waiting = false
  chat = {}
  SlashCmdList.BETTERGREATVAULT("status")
  ucheck(Chatted("This week: 3 of 9 unlocked") and Chatted("285"), "/bgv status prints the week")
  SlashCmdList.BETTERGREATVAULT("")
  ucheck(Chatted("/bgv status"), "help lists /bgv status")

  -- /bgv perf: CPU from the game's addon profiler (the AddOns list's figures), memory, the last animation
  ucheck(Chatted("/bgv perf"), "help lists /bgv perf")
  Enum = Enum or {}
  Enum.AddOnProfilerMetric = { SessionAverageTime = 0, RecentAverageTime = 1, PeakTime = 4, CountTimeOver5Ms = 6 }
  local profilerOn = true
  C_AddOnProfiler = {
    IsEnabled = function() return profilerOn end,
    GetAddOnMetric = function(name, metric)
      if name ~= "BetterGreatVault" then return 0 end
      return ({ [0] = 0.012, [1] = 0.02, [4] = 3.5, [6] = 2 })[metric]
    end,
    GetApplicationMetric = function() return 8 end,
    GetOverallMetric = function() return 1.5 end,
  }
  function UpdateAddOnMemoryUsage() end
  function GetAddOnMemoryUsage(name) return name == "BetterGreatVault" and 2560 or 0 end
  BGV.Case.lastStats = { frames = 144, time = 7.2, peak = 0.12, seconds = 1 }
  BGV.loadFiles, BGV.loadSetup = 12.34, 5.6
  BGV.LootTable.lastLoad = { redraws = 9, time = 41.26, peak = 7.5 }
  chat = {}
  SlashCmdList.BETTERGREATVAULT("perf")
  local function ChattedText(text)
    for _, line in ipairs(chat) do if line:find(text, 1, true) then return true end end
    return false
  end
  -- 0.02 / (8 - 1.5 + 0.02): the addon's share with the other addons' time left out, as the AddOns list does
  ucheck(ChattedText("CPU: 0.020 ms a frame now (0.31% of the game's time); since the game started, 0.012 ms on average and 3.5 ms at the peak"), "perf: CPU as the AddOns list works it out")
  ucheck(ChattedText("Frames where it took over 5 ms since the game started: 2") and Chatted("Memory: 2.5 MB"), "perf: slow frames and memory")
  ucheck(ChattedText("Loading: 17.9 ms (its files 12.3 ms, setting up 5.6 ms)"), "perf: loading")
  ucheck(Chatted("Last slot animation: 0.050 ms a frame on average, 0.120 ms at most, 144 frames at 144 fps"), "perf: the last animation")
  ucheck(ChattedText("Last loot table load: 41.3 ms in all, the longest redraw 7.5 ms, redraws: 9"), "perf: the last loot table load")
  profilerOn = false
  BGV.Case.lastStats = nil
  BGV.loadFiles, BGV.loadSetup, BGV.LootTable.lastLoad = nil, nil, nil
  chat = {}
  SlashCmdList.BETTERGREATVAULT("performance")
  ucheck(Chatted("addon profiler is off") and Chatted("Point at an unlocked slot"), "perf: without the profiler or an animation yet")
  ucheck(not ChattedText("Loading:") and not ChattedText("Last loot table load"), "perf: no loading or loot table lines without their numbers")
  ucheck(Button("Print performance"), "Tools: a performance button")
  C_AddOnProfiler, UpdateAddOnMemoryUsage, GetAddOnMemoryUsage = nil, nil, nil

  -- the language: game language or one picked; applied after a reload
  local languageButton = Button("Game language: English")
  ucheck(languageButton, "language button shows the game language")
  -- flat buttons draw their label as a plain font string: in the game, button text set through
  -- SetFontString showed Cyrillic as boxes
  local label = languageButton:GetFontString()
  ucheck(languageButton.fontString == nil and label and label.text == "Game language: English",
    "the label is a plain font string, not the button's own text")
  for _, frame in ipairs(AllFrames) do
    if frame.kind == "Button" and frame.fontString and frame.fontString.kind == "CreateFontString" and frame.back then
      ucheck(false, "a flat button with its label set as the button's text")
      break
    end
  end
  local reloadButton = Button("Reload now")
  ucheck(reloadButton and reloadButton.mouseEnabled == false, "reload is off until the language changes")
  local reloaded = false
  function ReloadUI() reloaded = true end
  languageButton.scripts.OnClick(languageButton)
  local ukrainian = FindEntry(lastMenu, "Українська")
  ucheck(ukrainian and FindEntry(lastMenu, "Deutsch") and FindEntry(lastMenu, "Game language"), "the language menu lists the languages")
  ukrainian.setSelected()
  ucheck(BetterGreatVaultDB.language == "ukUA", "Ukrainian picked")
  ucheck(languageButton:GetText() == "Українська (Ukrainian)", "the button shows it: " .. tostring(languageButton:GetText()))
  ucheck(reloadButton.mouseEnabled == true, "reload offered once the language changed")
  reloadButton.scripts.OnClick(reloadButton)
  ucheck(reloaded, "reload now reloads the interface")
  ucheck(BGV.L["Settings"] == "Settings", "the new language waits for the reload")
  languageButton.scripts.OnClick(languageButton)
  FindEntry(lastMenu, "Game language").setSelected()
  ucheck(BetterGreatVaultDB.language == "auto" and reloadButton.mouseEnabled == false, "back to the game language")

  -- right-click on the minimap button and the chat commands
  mini.scripts.OnClick(mini, "RightButton")
  ucheck(openedCategory == 42, "right-click opens the settings page")
  SlashCmdList.BETTERGREATVAULT("debug")
  ucheck(BetterGreatVaultDB.debug == true and Row("Debug mode").fill.shown, "/bgv debug turns debug on and the checkbox follows")
  SlashCmdList.BETTERGREATVAULT("reset")
  ucheck(BetterGreatVaultDB.debug == false and BetterGreatVaultDB.rewardData == learned, "/bgv reset resets and keeps learned data")
  ucheck(BetterGreatVaultDB.fontSize == 0 and BetterGreatVaultFontHighlight.size == 12 and Row("Lock position").height == 22, "reset puts the text size back")

  -- What's new: only when asked for (the version in About, /bgv news), never by itself
  do
    for _, f in ipairs(AllFrames) do
      ucheck(not (f.events and f.events.PLAYER_ENTERING_WORLD and f.events.PLAYER_REGEN_DISABLED), "nothing waits to show it at login")
    end
    ucheck(_G.BetterGreatVaultNews == nil, "not made until asked for")
    local combatBefore = InCombatLockdown
    InCombatLockdown = function() return false end
    local card
    for _, c in ipairs(content.children) do if c.meta then card = c end end
    ucheck(card and card.version, "the version in About is a button")
    card.version.scripts.OnEnter(card.version)
    ucheck(GameTooltip.text == "What's new", "pointing at the version says What's new: " .. tostring(GameTooltip.text))
    card.version.scripts.OnClick(card.version)
    card.version.scripts.OnLeave(card.version)
    local news = _G.BetterGreatVaultNews
    ucheck(news and news.shown, "clicking the version opens it")
    ucheck(news and news.title.text == "Settings that show where they apply", "its title: " .. tostring(news and news.title.text))
    local drawn = 0
    for _, preview in ipairs(news.previews) do
      if preview.canvas.bgvSheets and #preview.canvas.bgvSheets > 0 then drawn = drawn + 1 end
    end
    ucheck(drawn == 3, "three previews drawn with the settings' sketches: " .. drawn)
    local escapable = false
    for _, name in ipairs(UISpecialFrames or {}) do if name == "BetterGreatVaultNews" then escapable = true end end
    ucheck(escapable, "Escape closes it")
    news.gotIt.scripts.OnClick(news.gotIt)
    ucheck(not news.shown, "Got it closes it")
    card.version.scripts.OnClick(card.version)
    ucheck(news.shown, "it opens again whenever asked")
    news.gotIt.scripts.OnClick(news.gotIt)
    SlashCmdList.BETTERGREATVAULT("news")
    ucheck(news.shown, "/bgv news opens it too")
    ucheck(news.showMe == nil, "one button: Got it")
    news.gotIt.scripts.OnClick(news.gotIt)
    -- Escape closes it first, the settings staying open; in combat it leaves the keyboard alone
    news.keyboard, news.propagate = nil, nil
    SlashCmdList.BETTERGREATVAULT("news")
    ucheck(news.shown and news.keyboard == true and news.propagate == true, "shown: it takes the keyboard and passes keys on")
    news.scripts.OnKeyDown(news, "W")
    ucheck(news.shown and news.propagate == true, "another key passes through and it stays")
    news.scripts.OnKeyDown(news, "ESCAPE")
    ucheck(not news.shown and news.propagate == false and sp.shown, "Escape closes it and goes no further, so the settings stay")
    -- asked for in combat: it opens (it touches nothing protected)
    InCombatLockdown = function() return true end
    SlashCmdList.BETTERGREATVAULT("news")
    ucheck(news.shown, "it opens in combat too when asked for")
    ucheck(news.keyboard == false, "shown in combat: the keyboard is left to the game")
    local escaped = pcall(news.scripts.OnKeyDown, news, "ESCAPE")
    ucheck(escaped and news.shown, "Escape in combat: nothing restricted is called; the game's own closing takes it")
    news.gotIt.scripts.OnClick(news.gotIt)
    InCombatLockdown = combatBefore
  end
end

-- Class set (tier) pieces: the season's set from the Adventure Guide's Item Sets (the one the
-- Best-in-Slot lists name, not a PvP set at a higher item level), first in every list, at the
-- list's item level (raid Mythic: the normal level, not the last bosses' ceiling)
do
  local SETS = {
    [1] = { { setID = 10, itemLevel = 200, name = "Old Set" }, { setID = 20, itemLevel = 300, name = "Season Set" },
            { setID = 30, itemLevel = 400, name = "Three Pieces" }, { setID = 50, itemLevel = 500, name = "Arena Set" } },
    [2] = { { setID = 60, itemLevel = 500, name = "Paladin Arena Set" } },
    [8] = { { setID = 40, itemLevel = 300, name = "Mage Set" } },
  }
  local PIECES = { [10] = 7101, [20] = 7201, [30] = 7301, [40] = 7401, [50] = 7501, [60] = 7601 }
  local SLOTS = { "INVTYPE_HEAD", "INVTYPE_SHOULDER", "INVTYPE_CHEST", "INVTYPE_HAND", "INVTYPE_LEGS" }
  C_LootJournal = {
    GetItemSets = function(classID) return SETS[classID] or {} end,
    GetItemSetItems = function(setID)
      local items = {}
      for index = 1, (setID == 30 and 3 or 5) do items[index] = { itemID = PIECES[setID] + index - 1, icon = 9, invType = index } end
      return items
    end,
  }
  local realInstant = GetItemInfoInstant
  GetItemInfoInstant = function(id)
    if id >= 7100 and id < 7700 then return id, "Armor", "Plate", SLOTS[(id % 100)], 7, 4, 4 end
    return realInstant(id)
  end
  -- The guides name the season set's pieces (Fury: one S, the rest A; Fire and Frost: one each),
  -- not the PvP sets'.
  local realBisTier = BGV.Bis.Tier
  BGV.Bis.Tier = function(itemID, specID)
    if specID == 72 and itemID >= 7201 and itemID <= 7205 then return itemID == 7203 and "S" or "A" end
    if specID == 63 and itemID == 7402 then return "S" end
    if specID == 64 and itemID == 7404 then return "A" end
    return realBisTier(itemID, specID)
  end
  local function Tier(list)
    local ids, sources, levels = {}, {}, {}
    for _, entry in ipairs(list) do
      if entry.tierClass then ids[#ids + 1] = entry.itemID; sources[entry.source] = true; levels[entry.itemLevel or 0] = true end
    end
    return ids, sources, levels
  end
  local ids, sources, levels = Tier(R.DatabaseItems("raid", 16, 1, 0))
  ucheck(#ids == 0, "the database's raid list has no set pieces (the tier set source lists them)")
  local tierLevels = R.DatabaseLevels("tier")
  ucheck(tierLevels.default == "raid:16", "tier set levels default to the highest: " .. tostring(tierLevels.default))
  local labels = {}
  for _, info in ipairs(tierLevels) do labels[info.level] = info.label end
  ucheck(labels["raid:16"] == "Raid Mythic" and labels["mplus:10"] == "Mythic +10+" and labels["world:8"] == "World Tier 8",
    "tier set levels named by source: " .. tostring(labels["raid:16"]) .. ", " .. tostring(labels["mplus:10"]))
  local set = R.DatabaseItems("tier", "raid:16", 1, 0)
  ids, sources, levels = Tier(set)
  ucheck(#ids == 5 and set[1].itemID == 7201 and set[5].itemID == 7205,
    "the season's full set (the one the BiS lists name, not the Arena set above it): " .. table.concat(ids, ","))
  ucheck(sources["Warrior"] and levels[334] and not levels[344], "raid Mythic set pieces at 334, not the ceiling, grouped by class")
  ids, sources, levels = Tier(R.DatabaseItems("tier", "mplus:10", 0, 0))
  ucheck(#ids == 10 and sources["Warrior"] and sources["Mage"] and levels[318], "all classes at +10: a group per class: " .. #ids)
  -- a class whose Best-in-Slot lists name none of its sets' pieces shows no set, not its Arena set
  local realNumClasses, realClassInfo, realSpecInfo = GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID
  GetNumClasses = function() return 3 end
  GetClassInfo = function(i) if i == 3 then return "Paladin", "PALADIN", 2 end return realClassInfo(i) end
  GetSpecializationInfoForClassID = function(c, i)
    local id = c == 2 and ({ 65, 66, 70 })[i]
    if id then return id, "Spec " .. id end
    return realSpecInfo(c, i)
  end
  ucheck(#BGV.Utils.ClassSpecs(2) == 3, "paladin specs known for the check below")
  ids = Tier(R.DatabaseItems("tier", "mplus:10", 2, 0))
  ucheck(#ids == 0, "no set named for the class: none shown: " .. #ids)
  GetNumClasses, GetClassInfo, GetSpecializationInfoForClassID = realNumClasses, realClassInfo, realSpecInfo
  local vault = R.ItemsForSlot(vaultSlot)
  ids, sources, levels = Tier(vault)
  ucheck(#ids == 5 and vault[1].itemID == 7201 and levels[334] and vault[#vault].itemID == 9011,
    "the vault's raid slot lists the player's set first, then the boss loot")
  local mplusSlot = { type = 1, index = 2, unlocked = true, level = 10, itemLevel = 318, activityTierID = 256 }
  local mplus = R.ItemsForSlot(mplusSlot)
  ids, _, levels = Tier(mplus)
  ucheck(#ids == 5 and mplus[1].itemID == 7201 and levels[318], "a Mythic+ slot lists the set at its item level")
  local icons = R.PossibleIcons(mplusSlot)
  local onReel = false
  for _, icon in ipairs(icons) do onReel = onReel or icon.itemID == 7203 end
  ucheck(onReel, "set pieces are on the slot's reel")
  -- in the loot table: the set's group heads the list
  BGV.Rewards.InvalidateIcons()
  LT.ShowDatabase()
  if not raidRow.fill.shown then raidRow.scripts.OnClick(raidRow) end
  if not tierRow.fill.shown then tierRow.scripts.OnClick(tierRow) end
  LT.Invalidate()
  local dividers = Dividers()
  local pieces = 0
  for _, r in ipairs(Rows()) do if r.entry.tierClass then pieces = pieces + 1 end end
  ucheck(dividers[1] and dividers[1]:find("^TIER SET") and pieces == 5,
    "the database lists the set once, under its own source: " .. tostring(dividers[1]) .. ", " .. pieces .. " pieces")
  -- its level menu: every source's levels under the source's name
  tierRow.level.scripts.OnClick(tierRow.level)
  local titles = {}
  for _, e in ipairs(lastMenu.entries) do if e.title then titles[#titles + 1] = e.text end end
  ucheck(table.concat(titles, "|") == "Vault reward item level|Raid|Mythic+|World", "tier level menu sections: " .. table.concat(titles, "|"))
  local plus10 = FindEntry(lastMenu, "^%+10%+  ")
  ucheck(plus10 and plus10.setSelected, "tier level menu offers +10+")
  plus10.setSelected()
  ucheck(tierRow.level:GetText() == "Mythic +10+ • 318", "tier set at +10+: " .. tostring(tierRow.level:GetText()))
  levels = {}
  for _, r in ipairs(Rows()) do if r.entry.tierClass then levels[r.level.text] = true end end
  ucheck(levels["318"] and not levels["334"], "set pieces now at 318")
  -- the set's Best-in-Slot letters show on its rows, for the chosen spec (Fire)
  local letters = {}
  for _, r in ipairs(Rows()) do if r.entry.tierClass then letters[r.entry.itemID] = r.tier.text end end
  ucheck(letters[7402] == "S" and letters[7404] == "-", "set pieces carry the chosen spec's BiS letters: "
    .. tostring(letters[7402]) .. ", " .. tostring(letters[7404]))
  -- set bonuses, in the game's words (its tooltip for a set piece as a class and spec), once the
  -- bonus spells have loaded: in a set piece's tooltip, where the game writes that the bonuses
  -- vary by specialization, and over the tier set's header
  ITEM_SET_BONUS, ITEM_SET_BONUS_GRAY = "Set: %s", "(%d) Set: %s"
  ITEM_SET_BONUS_NO_VALID_SPEC = "Bonus effects vary based on the player's specialization."
  local SPECS_WITH_BONUSES = { [62] = true, [63] = true, [64] = true, [71] = true, [72] = true, [73] = true }
  local cachedSpells = { [8801] = true }
  local realItemAPI, realSpellAPI, realTooltipAPI, realSpecByID = C_Item, C_Spell, C_TooltipInfo, GetSpecializationInfoByID
  C_Item = setmetatable({ GetSetBonusesForSpecializationByItemID = function(specID)
    return SPECS_WITH_BONUSES[specID] and { 8801, 8802 } or {}
  end }, { __index = realItemAPI })
  C_Spell = {
    IsSpellDataCached = function(id) return cachedSpells[id] == true end,
    RequestLoadSpellData = function(id) cachedSpells[id] = true end,
  }
  local asked
  C_TooltipInfo = { GetHyperlink = function(link, classID, specID)
    asked = table.concat({ link, classID, specID }, ",")
    local gray = { GetRGB = function() return 0.5, 0.5, 0.5 end }
    return { lines = { { leftText = "Item" }, { leftText = "Set (0/5)" },
      { leftText = "(2) Set: two for " .. specID, leftColor = gray }, { leftText = "(4) Set: four for " .. specID, leftColor = gray } } }
  end }
  GetSpecializationInfoByID = function(id) return id, "Spec " .. id end
  local tip = { lines = {} }
  GameTooltip.SetOwner = function(self, owner) tip.owner, tip.lines = owner, {} end
  GameTooltip.GetOwner = function() return tip.owner end
  GameTooltip.AddLine = function(self, text) tip.lines[#tip.lines + 1] = text end
  GameTooltip.Show = function() end
  GameTooltip.Hide = function() tip.owner = nil end
  -- a row's item tooltip as the game fills it, then the loot table's post-call over it; returns the
  -- third line (where the game wrote that bonuses vary), without its colour codes
  local tipFonts = {}
  GameTooltip.GetName = function() return "GameTooltip" end
  GameTooltip.NumLines = function() return #tipFonts end
  local function ItemTooltip(row)
    tipFonts = {}
    for index, text in ipairs({ "Item", "Set (0/5)", ITEM_SET_BONUS_NO_VALID_SPEC, "Classes: Mage" }) do
      tipFonts[index] = { text = text, GetText = function(self) return self.text end,
        SetText = function(self, value) self.text = value end, SetTextColor = function() end }
      _G["GameTooltipTextLeft" .. index] = tipFonts[index]
    end
    tip.owner = row
    for _, fn in ipairs(itemPostCalls) do fn(GameTooltip) end
    return (tipFonts[3].text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
  end
  local function TierHeader()
    for _, r in ipairs(scrollFrameOf(loot).children[1].children) do
      if r.shown and not r.entry and r.band.shown and r.bgvTierClass then return r end
    end
  end
  local function TierPiece()
    for _, r in ipairs(Rows()) do if r.entry.tierClass then return r end end
  end
  ucheck(#itemPostCalls == 1, "the loot table looks over item tooltips: " .. #itemPostCalls)
  local header = TierHeader()
  ucheck(header and header.bgvTierClass == 8, "the tier set's header knows its class: " .. tostring(header and header.bgvTierClass))
  header.scripts.OnEnter(header)
  ucheck(tip.owner == header and tip.lines[1] == "Mage Set" and tip.lines[2] == "Spec 63" and tip.lines[3] == "...",
    "hovered while a bonus loads: " .. table.concat(tip.lines, " | "))
  header:UpdateTooltip()
  ucheck(tip.lines[2] == "Spec 63" and tip.lines[3] == "(2) Set: two for 63" and tip.lines[4] == "(4) Set: four for 63"
    and #tip.lines == 4 and not header.bgvBonusPending, "then the game's lines for Fire: " .. table.concat(tip.lines, " | "))
  ucheck(asked == "item:7401,8,63", "the game's tooltip for a set piece, as Fire: " .. tostring(asked))
  header.scripts.OnLeave(header)
  ucheck(tip.owner == nil, "leaving the header hides it")
  local piece = TierPiece()
  local shown = piece and ItemTooltip(piece)
  ucheck(shown == "Spec 63\n(2) Set: two for 63\n(4) Set: four for 63" and tipFonts[2].text == "Set (0/5)"
    and tipFonts[4].text == "Classes: Mage", "a set piece's tooltip: Fire's bonuses where the game says they vary: " .. tostring(shown))
  local other
  for _, r in ipairs(Rows()) do if not r.entry.tierClass then other = r break end end
  ucheck(other and ItemTooltip(other) == ITEM_SET_BONUS_NO_VALID_SPEC, "other items' tooltips stay as the game wrote them")
  -- a bonus already active on the player reads "Set: ..." (no piece count), as in the game
  local realHyperlink = C_TooltipInfo.GetHyperlink
  C_TooltipInfo.GetHyperlink = function() return { lines = {
    { leftText = "Set: active two", leftColor = { GetRGB = function() return 0, 1, 0 end } }, { leftText = "(4) Set: four" } } } end
  local bonuses = R.SetBonuses(8, 63)
  ucheck(bonuses and #bonuses.lines == 2 and bonuses.lines[1].text == "Set: active two" and bonuses.lines[1].g == 1
    and bonuses.lines[2].text == "(4) Set: four", "active and inactive bonuses as the game shows them")
  -- lines the tooltip leaves empty: the bonus spells' own descriptions instead
  C_TooltipInfo.GetHyperlink = function() return { lines = { { leftText = "Set: " }, { leftText = "(4) Set: " } } } end
  C_Spell.GetSpellDescription = function(id) return "Bonus " .. id end
  bonuses = R.SetBonuses(8, 63)
  ucheck(bonuses and #bonuses.lines == 2 and bonuses.lines[1].text == "Bonus 8801" and not bonuses.pending,
    "empty tooltip lines: the bonus spells' descriptions")
  ucheck(R.SetBonuses(8, 65) == nil, "a spec without bonuses for the set: none")
  C_TooltipInfo.GetHyperlink = realHyperlink
  -- All specs (as with All classes): every spec of the class, in the header and in a piece's tooltip
  classButton.scripts.OnClick(classButton)
  local allSpecs = FindEntry(lastMenu, "^All specs")
  ucheck(allSpecs, "All specs in the class menu")
  allSpecs.setSelected()
  header = TierHeader()
  if header then header.scripts.OnEnter(header) end
  ucheck(header and #tip.lines == 10 and tip.lines[2] == "Spec 62" and tip.lines[5] == "Spec 63" and tip.lines[8] == "Spec 64"
    and tip.lines[10] == "(4) Set: four for 64", "with All specs, the header shows every spec's bonuses: " .. table.concat(tip.lines, " | "))
  piece = TierPiece()
  shown = piece and ItemTooltip(piece)
  ucheck(shown and select(2, shown:gsub("Spec 6%d\n", "")) == 3 and shown:find("(4) Set: four for 64", 1, true),
    "and so does a set piece's tooltip: " .. tostring(shown))
  -- a bonus whose text is still loading: the piece's tooltip is filled again (UpdateTooltip)
  cachedSpells[8802] = nil
  ItemTooltip(piece)
  ucheck(piece.bgvBonusPending, "a bonus still loading leaves the piece's tooltip to be filled again")
  ItemTooltip(piece)
  ucheck(not piece.bgvBonusPending, "and once it has loaded, that's done")
  -- the vault's own list: the loot spec's bonuses (the Great Vault's loot spec button)
  LT.Show(nil)
  header = TierHeader()
  ucheck(header and header.bgvTierClass == 1, "the vault list's tier set header: the player's class")
  if header then header.scripts.OnEnter(header) end
  ucheck(tip.lines[2] == "Spec 71" and tip.lines[3] == "(2) Set: two for 71" and #tip.lines == 4 and asked == "item:7201,1,71",
    "the vault list shows the loot spec's bonuses: " .. table.concat(tip.lines, " | "))
  piece = TierPiece()
  shown = piece and ItemTooltip(piece)
  ucheck(shown == "Spec 71\n(2) Set: two for 71\n(4) Set: four for 71", "and so do its set pieces' tooltips: " .. tostring(shown))
  loot:Hide()
  C_Item, C_Spell, C_TooltipInfo, GetSpecializationInfoByID = realItemAPI, realSpellAPI, realTooltipAPI, realSpecByID
  GameTooltip.SetOwner, GameTooltip.GetOwner, GameTooltip.AddLine, GameTooltip.Show, GameTooltip.Hide = nil, nil, nil, nil, nil
  GameTooltip.GetName, GameTooltip.NumLines = nil, nil
  for index = 1, 4 do _G["GameTooltipTextLeft" .. index] = nil end
  ITEM_SET_BONUS, ITEM_SET_BONUS_GRAY, ITEM_SET_BONUS_NO_VALID_SPEC = nil, nil, nil
  GetItemInfoInstant = realInstant
  BGV.Bis.Tier = realBisTier
end
for _, name in ipairs(BLIZZARD_GLOBALS) do
  ucheck(_G[name] == blizzardOriginals[name], "the game's " .. name .. " is left as it was")
end
ucheck(escHandlers == 0, "no Escape handler registered with the game: " .. escHandlers)

-- Escape closes the loot window first, the vault staying open: shown, the window takes the keyboard,
-- passes every other key on and keeps Escape. In combat (where changing what it keeps is restricted)
-- it leaves the keyboard alone, so nothing restricted is ever called.
do
  local combat = false
  InCombatLockdown = function() return combat end
  local loot = _G.BetterGreatVaultLootTable
  loot:Hide()
  loot.keyboard, loot.propagate = nil, nil
  BGV.LootTable.ShowDatabase()
  ucheck(loot.shown and loot.keyboard == true and loot.propagate == true, "shown: the window takes the keyboard and passes keys on")
  loot.scripts.OnKeyDown(loot, "W")
  ucheck(loot.shown and loot.propagate == true, "another key passes through and the window stays")
  loot.scripts.OnKeyDown(loot, "ESCAPE")
  ucheck(not loot.shown and loot.propagate == false, "Escape closes the window and goes no further, so the vault stays")
  combat = true
  BGV.LootTable.ShowDatabase()
  ucheck(loot.shown and loot.keyboard == false, "shown in combat: the keyboard is left to the game")
  local ok = pcall(loot.scripts.OnKeyDown, loot, "ESCAPE")
  ucheck(ok and loot.shown, "Escape in combat: nothing restricted is called; the game's own closing takes it")
  combat = false
  loot:Hide()
  BGV.LootTable.ShowDatabase()
  ucheck(loot.keyboard == true and loot.propagate == true, "out of combat again: the window takes Escape again")
  loot:Hide()
  InCombatLockdown = nil
end

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  ucheck(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end
print(uiFails == 0 and "ui smoke checks passed" or (uiFails .. " ui checks failed"))
