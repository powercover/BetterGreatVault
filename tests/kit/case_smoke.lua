-- Case.lua's opening styles, each run through opening, open and closing on a fake 60 Hz clock:
-- the slot must come back to rest the same way every time, and the work per tick stays small.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("CASE FAIL: " .. message) end end
local calls = 0

-- Frame fields Blizzard's frames have (read as fields, not methods)
local FIELDS = { ItemFrame = true, Background = true, ModelScene = true, Threshold = true, Progress = true }
local METHODS
local function Region(kind, parent)
  local r = { kind = kind, shown = true, alpha = 1, _parent = parent, children = {}, regions = {}, masks = {}, level = 1, scripts = {} }
  return setmetatable(r, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") or FIELDS[k] then return nil end
    return METHODS[k] or function() calls = calls + 1 end
  end })
end
METHODS = {
  Show = function(self) calls = calls + 1; self.shown = true end,
  Hide = function(self) calls = calls + 1; self.shown = false end,
  SetShown = function(self, v) calls = calls + 1; self.shown = v and true or false end,
  IsShown = function(self) return self.shown end,
  IsVisible = function(self) return self.shown end,
  SetAlpha = function(self, a) calls = calls + 1; self.alpha = a end,
  GetAlpha = function(self) return self.alpha end,
  SetSize = function(self, w, h) calls = calls + 1; self.w, self.h = w, h end,
  SetWidth = function(self, w) calls = calls + 1; self.w = w end,
  SetHeight = function(self, h) calls = calls + 1; self.h = h end,
  GetWidth = function(self) return self.w or (self._parent and self._parent:GetWidth()) or 219 end,
  GetHeight = function(self) return self.h or (self._parent and self._parent:GetHeight()) or 126 end,
  SetFrameLevel = function(self, v) calls = calls + 1; self.level = v end,
  GetFrameLevel = function(self) return self.level end,
  CreateTexture = function(self, _, layer, _, sub)
    calls = calls + 1
    local t = Region("Texture", self); t.layer, t.sublevel = layer, sub
    table.insert(self.regions, t)
    return t
  end,
  CreateFontString = function(self) local t = Region("FontString", self); table.insert(self.regions, t); return t end,
  CreateMaskTexture = function(self) calls = calls + 1; return Region("Mask", self) end,
  AddMaskTexture = function(self, mask) calls = calls + 1; self.masks[mask] = true end,
  RemoveMaskTexture = function(self, mask) calls = calls + 1; self.masks[mask] = nil end,
  SetTexture = function(self, file, wrap) calls = calls + 1; self.file = file; self.wrap = wrap end,
  GetTexture = function(self) return self.file end,
  SetAtlas = function(self, a) calls = calls + 1; self.atlas = a end,
  GetAtlas = function(self) return self.atlas end,
  SetRotation = function(self, r) calls = calls + 1; self.rotation = r end,
  SetVertexColor = function(self, r, g, b) calls = calls + 1; self.color = { r, g, b } end,
  SetDesaturated = function(self, v) calls = calls + 1; self.grey = v end,
  SetTexCoord = function(self, l, r, t, b) calls = calls + 1; self.coords = { l, r, t, b } end,
  SetScript = function(self, name, fn) self.scripts[name] = fn end,
  SetText = function(self, t) calls = calls + 1; self.text = t end,
  GetText = function(self) return self.text end,
  HookScript = function(self, name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end fn(...) end
  end,
  GetScript = function(self, name) return self.scripts[name] end,
  GetParent = function(self) return self._parent end,
  SetParent = function(self, p) self._parent = p end,
  GetChildren = function(self) return unpack(self.children) end,
  IsMouseOver = function() return false end,
  CreateAnimationGroup = function(self)
    local g = Region("AnimationGroup", self)
    g.CreateAnimation = function() return Region("Animation", g) end
    g.Play = function(s) s.playing = true end
    g.Stop = function(s) s.playing = false end
    g.IsPlaying = function(s) return s.playing == true end
    return g
  end,
}
function CreateFrame(kind, name, parent)
  calls = calls + 1
  local f = Region(kind, parent)
  if parent then table.insert(parent.children, f) end
  if name then _G[name] = f end
  return f
end

-- the clock and the tickers
local clock = 100
function GetTime() return clock end
C_Timer = { After = function(_, fn) fn() end }
function debugprofilestop() return os.clock() * 1000 end
local driver, fps = nil, 60
local driverFrames = 0
local function Run(seconds)
  for _ = 1, math.floor(seconds * fps + 0.5) do
    clock = clock + 1 / fps
    local update = driver and driver.scripts.OnUpdate
    if update then
      driverFrames = driverFrames + 1
      update(driver, 1 / fps)
    end
  end
end
local function LiveTickers()
  return (driver and driver.scripts.OnUpdate) and 1 or 0
end

function GetLocale() return "enUS" end
UIParent = Region("Frame")
GameTooltip = Region("GameTooltip")
BetterGreatVaultDB = {}
local SPEC = 71
function GetSpecialization() return 1 end
function GetSpecializationInfo() return SPEC end
function GetLootSpecialization() return 0 end

local BGV = {}
for _, path in ipairs({ "Locales/Locales.lua", "Utils.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end
local TIERS = {}
BGV.Bis = { Tier = function(itemID) return TIERS[itemID] end }
BGV.Rewards = { PossibleIcons = function() return {}, false end }
assert(loadfile("Case.lua"))("BetterGreatVault", BGV)
assert(loadfile("CaseStyles.lua"))("BetterGreatVault", BGV)
local Case = BGV.Case
driver = UIParent.children[#UIParent.children]
check(driver and driver.scripts.OnUpdate == nil, "no per-frame work at load")

local vaultShown = true
local vault = CreateFrame("Frame", "WeeklyRewardsFrame")
vault.IsShown = function() return vaultShown end
local slot = CreateFrame("Frame", nil, vault)
slot.w, slot.h, slot.level = 219, 126, 200
slot.bgvHit = CreateFrame("Button", nil, slot)
slot.bgvText = CreateFrame("Frame", nil, slot)
slot.bgvSlot = { unlocked = true }
local hovering = false
function GetMouseFoci() return { hovering and slot.bgvHit or UIParent } end

local ICONS = {}
for i = 1, 12 do ICONS[i] = { icon = 5000 + i, itemID = 9000 + i } end
TIERS[9001], TIERS[9005], TIERS[9007] = "S", "A", "S"
local fx = Case.Ensure(slot)
fx.icons, fx.iconKey, fx.iconCount, fx.iconsPending = ICONS, ICONS, #ICONS, false

-- What a slot at rest looks like, whatever style it last opened with.
local function MaskedTextures()
  local n = 0
  for _, cell in ipairs(fx.cells) do
    for _ in pairs(cell.icon.masks) do n = n + 1 end
    for _ in pairs(cell.back.masks) do n = n + 1 end
  end
  for _ in pairs(fx.shade.masks) do n = n + 1 end
  for _ in pairs(fx.markerLine.masks) do n = n + 1 end
  return n + (fx.masked and #fx.masked or 0)
end
local function LiveParticles()
  local n = 0
  for i = 1, 32 do
    local p = fx.parts and fx.parts[i]
    if p and (p.live or p.texture.shown) then n = n + 1 end
  end
  return n
end
local function ArtShown()
  local shown = {}
  local function Look(name, ...)
    for i = 1, select("#", ...) do
      local region = select(i, ...)
      if region and region.shown then shown[#shown + 1] = name .. i end
    end
  end
  if fx.vaultArt then Look("vault.light", fx.vaultArt.light) end
  if fx.banditArt then Look("bandit", fx.banditArt.frame, fx.banditArt.slats) end
  if fx.arcaneArt then local a = fx.arcaneArt; Look("arcane", a.back, a.runes, a.glow, a.ring, a.edge, a.flash) end
  if fx.frostArt then
    local a = fx.frostArt
    Look("frost", a.plate, a.cracks, a.edge, a.vignettes[1], a.vignettes[2])
    for _, s in ipairs(a.shards) do Look("shard", s.texture) end
  end
  if fx.felArt then Look("fel", fx.felArt.edge, fx.felArt.heat) end
  if fx.cartoonArt then Look("cartoon", fx.cartoonArt.ring, fx.cartoonArt.lines) end
  for id, art in pairs(fx.styleArt or {}) do Look(id, unpack(art.list)) end
  return table.concat(shown, ",")
end
local function AtRest(label)
  check(fx.phase == "closed", label .. ": closed, got " .. tostring(fx.phase))
  check(not fx.shown and not fx.marker.shown and not fx.top.shown, label .. ": the case and its art layer are hidden")
  check(LiveTickers() == 0, label .. ": no ticker left running")
  check(fx.topDoor.shown and fx.bottomDoor.shown and fx.topDoor.alpha == 1 and fx.bottomDoor.alpha == 1, label .. ": the gates are shut over the face")
  check(fx.topDoor.h == 63 and fx.bottomDoor.h == 63, label .. ": each gate covers half: " .. tostring(fx.topDoor.h))
  check(fx.faceMode == "wipe" and fx.topDoor.level == fx.level + 8, label .. ": the face and levels are back")
  check(MaskedTextures() == 0, label .. ": no masks left on the reel")
  check(next(fx.topDoor.face.masks) == nil and next(fx.bottomDoor.face.masks) == nil and not fx.cut,
    label .. ": the gates are whole, no hole cut in them")
  check(LiveParticles() == 0, label .. ": no effects left")
  check(ArtShown() == "", label .. ": the style's art is put away: " .. ArtShown())
  check(fx.window.shown and fx.shade.alpha == 1, label .. ": the reel window is back")
  for _, gate in ipairs({ fx.topDoor, fx.bottomDoor }) do
    local c = gate.face.color
    check((c == nil or (c[1] == 1 and c[2] == 1 and c[3] == 1)) and not gate.face.grey, label .. ": the gates' face is its own color again")
  end
  for _, cell in ipairs(fx.cells) do
    if cell.icon.alpha ~= 1 then check(false, label .. ": the items are fully shown again") break end
  end
  local sizes = true
  for _, cell in ipairs(fx.cells) do if cell.icon.w ~= 40 or cell.back.alpha ~= 1 then sizes = false end end
  check(sizes, label .. ": the reel's items are back to size")
  check(slot.bgvText.bgvFadeTarget == 1, label .. ": the caption comes back")
end

-- every style, start to finish
local cost = {}
for _, style in ipairs(Case.STYLES) do
  local id = style.id
  BetterGreatVaultDB.vaultStyle = id
  hovering = true
  Case.Open(slot)
  check(fx.styleID == id and fx.phase == "opening", id .. ": opens in its style, got " .. tostring(fx.styleID))
  check(slot.bgvText.bgvFadeTarget == 0, id .. ": the caption fades")
  -- the art that sets the opening off is drawn over the gates: its layer is beside them (the game
  -- draws a clipping frame's contents with it, so inside the case it would be under them) and above
  check(fx.top._parent == slot and fx.top.shown and fx.top.level > fx.topDoor.level and fx.top.level > fx.bottomDoor.level,
    id .. ": the art layer is beside the gates and over them")
  check(fx.marker._parent == fx and fx.marker.level > fx.reel.level and fx.marker.level < fx.mid.level,
    id .. ": the marker is over the reel, under the gates and effects")
  Run(1.3)
  check(fx.phase == "open", id .. ": open after its opening, got " .. fx.phase)
  local before = calls
  Run(0.5)
  cost[#cost + 1] = string.format("%s %.0f", id, (calls - before) / 30)
  check((calls - before) / 30 < 160, id .. ": work per tick while open: " .. (calls - before) / 30)
  if id == "vault" then
    check(fx.faceMode == "slide" and fx.topDoor.h < 20, id .. ": the doors slid apart")
    check(fx.cells[1].ghosts ~= nil, id .. ": blur ghosts made")
  elseif id == "bandit" then
    local art = fx.banditArt
    check(not fx.window.shown and art.frame.shown and not fx.topDoor.shown, id .. ": the shutter is up on the cabinet")
    local painted = 0
    for _, column in ipairs(art.columns) do for _, cell in ipairs(column.cells) do if cell.icon.file then painted = painted + 1 end end end
    check(painted >= 12, id .. ": the three reels show loot: " .. painted)
  elseif id == "arcane" or id == "cartoon" then
    check(MaskedTextures() > 20, id .. ": the reel shows through the circle")
    check(fx.topDoor.level < fx.level, id .. ": the face is under the reel")
    check(fx.circle.w and fx.circle.w > 200, id .. ": open wide: " .. tostring(fx.circle.w))
  elseif id == "frost" then
    check(not fx.topDoor.shown and not fx.frostArt.plate.shown, id .. ": the ice shattered")
  elseif id == "fel" then
    check(not fx.topDoor.shown and not fx.felArt.edge.shown and fx.felArt.heat.shown, id .. ": the face has burned away")
  end
  hovering = false
  Run(2.5)
  AtRest(id)
end
print("work per tick while open (calls):", table.concat(cost, ", "))

-- held open a while, at an uneven frame rate, then left mid-opening on the way back: every style
-- keeps going and comes back to rest
for _, style in ipairs(Case.STYLES) do
  BetterGreatVaultDB.vaultStyle = style.id
  hovering = true
  Case.Open(slot)
  fps = 37
  Run(6)
  check(fx.phase == "open", style.id .. ": still open after a long hover: " .. fx.phase)
  hovering = false
  Run(0.2)
  hovering = true
  Case.Open(slot)
  fps = 144
  Run(0.3)
  hovering = false
  fps = 60
  Run(4)
  AtRest(style.id .. ", held open and pointed at again")
end

-- clouds: four shapes, mirrored, tilted and stretched at random, not one cloud copied
BetterGreatVaultDB.vaultStyle = "vault"
hovering = true
Case.Open(slot)
Run(0.15)
local shapes, mirrored, straight, tilts, widths = {}, false, false, {}, {}
for i = 1, 32 do
  local p = fx.parts[i]
  if p.live and p.file:find("CasePuffs$") then
    local l, r = p.texture.coords[1], p.texture.coords[2]
    shapes[math.floor(math.min(l, r) * 4 + 0.5)] = true
    if l > r then mirrored = true else straight = true end
    tilts[#tilts + 1] = p.texture.rotation
    widths[#widths + 1] = p.texture.w / p.texture.h
  end
end
local shapeCount = 0
for _ in pairs(shapes) do shapeCount = shapeCount + 1 end
table.sort(tilts)
table.sort(widths)
check(#tilts >= 6, "vault: dust clouds out: " .. #tilts)
check(shapeCount >= 3, "clouds in several shapes: " .. shapeCount)
check(mirrored and straight, "some clouds mirrored, some not")
check(tilts[#tilts] - tilts[1] > 0.3, "clouds tilted differently: " .. tostring(tilts[1]) .. " .. " .. tostring(tilts[#tilts]))
check(widths[#widths] - widths[1] > 0.1, "clouds stretched differently")
hovering = false
Run(2.5)
AtRest("after the clouds")

-- every rendered frame drives the animation, at any frame rate, with the same timings
for _, rate in ipairs({ 144, 60, 30 }) do
  fps = rate
  BetterGreatVaultDB.vaultStyle = "vault"
  hovering = true
  Case.Open(slot)
  local before = driverFrames
  Run(0.6)
  check(fx.phase == "opening", rate .. " fps: still opening at 0.6 s")
  Run(0.05)
  check(fx.phase == "open", rate .. " fps: open by 0.65 s, got " .. fx.phase)
  check(driverFrames - before == math.floor(0.6 * rate + 0.5) + math.floor(0.05 * rate + 0.5), rate .. " fps: one update a frame")
  hovering = false
  Run(2.5)
  AtRest(rate .. " fps")
  local stats = Case.lastStats
  check(stats and stats.frames > 0 and math.abs(stats.frames / stats.seconds - rate) < 1, rate .. " fps: the animation's frames recorded: "
    .. tostring(stats and stats.frames) .. " over " .. tostring(stats and stats.seconds))
end
fps = 60

-- Random: never the same twice in a row, never Classic
BetterGreatVaultDB.vaultStyle = "random"
local previous, seen = nil, {}
for _ = 1, 30 do
  hovering = true
  Case.Open(slot)
  check(fx.styleID ~= previous and fx.styleID ~= "classic", "random: " .. tostring(previous) .. " then " .. tostring(fx.styleID))
  previous = fx.styleID
  seen[fx.styleID] = true
  Case.Stop(slot)
end
local variety = 0
for _ in pairs(seen) do variety = variety + 1 end
check(variety >= 4, "random: a mix of styles: " .. variety)

-- Match specialization
BetterGreatVaultDB.vaultStyle = nil
check(Case.Choice() == "spec", "the default follows the specialization")
for spec, want in pairs({ [64] = "frost", [251] = "frostdk", [62] = "arcane", [1480] = "devourer", [577] = "fel", [581] = "vengeance",
    [267] = "destruction", [260] = "bandit", [268] = "brewmaster", [71] = "arms", [105] = "restodruid", [999] = "vault" }) do
  SPEC = spec
  check(Case.SpecStyle() == want, "spec " .. spec .. " opens as " .. want .. ", got " .. Case.SpecStyle())
end
-- every specialization in the game has a style of its own
local ALL_SPECS = { 250, 251, 252, 577, 581, 1480, 102, 103, 104, 105, 1467, 1468, 1473, 253, 254, 255, 62, 63, 64, 268, 269, 270,
  65, 66, 70, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 71, 72, 73 }
local owners = {}
for _, spec in ipairs(ALL_SPECS) do
  SPEC = spec
  local id = Case.SpecStyle()
  check(id ~= "vault" and not owners[id], "spec " .. spec .. " has a style of its own: " .. id .. (owners[id] and (" (also " .. owners[id] .. ")") or ""))
  owners[id] = spec
end
local extras = {}
for _, style in ipairs(Case.STYLES) do
  if not style.spec then extras[#extras + 1] = style.id end
  check(style.spec == nil or style.class, style.id .. ": a specialization's style names its class")
end
check(#Case.STYLES == 43 and table.concat(extras, ",") == "vault,classic,cartoon", "40 specialization styles and the three extras: " .. #Case.STYLES .. " " .. table.concat(extras, ","))
SPEC = 71
SPEC = 64
hovering = true
Case.Open(slot)
check(fx.styleID == "frost", "a frost mage's slot shatters")
Case.Stop(slot)
check(not fx.topDoor.shown and not fx.bottomDoor.shown and LiveTickers() == 0, "Stop: gates and ticker gone")

-- Classic turns back mid-way; the others finish opening first
BetterGreatVaultDB.vaultStyle = "classic"
Case.Open(slot)
Run(0.2)
hovering = false
Run(2 / 60)
check(fx.phase == "closing", "classic: leaving mid-way closes at once, got " .. fx.phase)
Run(1)
AtRest("classic, reversed")
BetterGreatVaultDB.vaultStyle = "vault"
hovering = true
Case.Open(slot)
Run(0.2)
hovering = false
Run(2 / 60)
check(fx.phase == "opening", "vault: finishes opening first")
Run(1.6)
AtRest("vault, left early")

-- pointed at again while closing: it opens again once closed
hovering = true
Case.Open(slot)
Run(1.3)
hovering = false
Run(0.2)
check(fx.phase == "closing", "closing")
hovering = true
Case.Open(slot)
Run(0.5)
check(fx.phase == "opening" or fx.phase == "open", "reopens after closing: " .. fx.phase)
check(Case.ActiveCount() == 1, "one slot driven: " .. Case.ActiveCount())
hovering = false
Run(3)
AtRest("reopened")

-- the vault closes with a slot open: shut at once
hovering = true
Case.Open(slot)
Run(1.3)
vaultShown = false
Run(1 / 60)
check(fx.phase == "closed" and LiveTickers() == 0 and not fx.shown, "vault closed: case shut at once")
check(fx.topDoor.shown and fx.bottomDoor.shown, "vault closed: the gates are shut over the face")
vaultShown = true

-- Rest after any style gives the same closed look
for _, style in ipairs(Case.STYLES) do
  BetterGreatVaultDB.vaultStyle = style.id
  hovering = true
  Case.Open(slot)
  Run(0.4)
  hovering = false
  Case.Rest(slot)
  AtRest("rest after " .. style.id)
end

-- animations off: nothing opens
BetterGreatVaultDB.disableAnimations = true
hovering = true
Case.Open(slot)
check(fx.phase == "closed" and LiveTickers() == 0, "animations off: no case")
BetterGreatVaultDB.disableAnimations = nil

-- the settings' preview: the pointed-at style on a slot of its own, with or without the vault:
-- it opens, spins a moment, closes and opens again, until its menu entry goes
vaultShown = false
local anchor = CreateFrame("Button", nil, UIParent)
Case.ShowPreview(anchor, "frost")
local panel
for _, c in ipairs(UIParent.children) do if c.fx and c.fx.preview then panel = c end end
local pfx = panel and panel.fx
check(panel and panel.shown and pfx.styleID == "frost" and pfx.phase == "opening", "preview: Frost Shatter opens beside the menu")
local function RunPreview(seconds)
  for _ = 1, math.floor(seconds * fps + 0.5) do
    clock = clock + 1 / fps
    local update = driver and driver.scripts.OnUpdate
    if update then update(driver, 1 / fps) end
    if panel.shown and panel.scripts.OnUpdate then panel.scripts.OnUpdate(panel, 1 / fps) end
  end
end
RunPreview(1.2)
check(pfx.phase == "open", "preview: open (Frost Shatter opens in 1s), the vault closed: " .. pfx.phase)
RunPreview(1.8)
check(pfx.phase == "closing", "preview: closes after a moment open: " .. pfx.phase)
RunPreview(1.5)
check(pfx.phase == "opening" and pfx.styleID == "frost", "preview: opens again: " .. pfx.phase)
-- Random: another style each time round
Case.ShowPreview(anchor, Case.RANDOM)
local seen, distinct = {}, 0
for _ = 1, 6 do
  if not seen[pfx.styleID] then seen[pfx.styleID], distinct = true, distinct + 1 end
  RunPreview(5)
end
check(distinct >= 2, "preview: Random plays different styles: " .. distinct)
-- the menu closes (its entry hides): the preview goes, and nothing keeps running
anchor.shown = false
RunPreview(0.1)
RunPreview(1)
check(not panel.shown and LiveTickers() == 0 and Case.ActiveCount() == 0, "preview: gone with its menu")
-- leaving the entry hides it too
anchor.shown = true
Case.ShowPreview(anchor, "vault")
Case.HidePreview()
RunPreview(0.1)
check(not panel.shown and LiveTickers() == 0, "preview: hidden on leaving the entry")
-- placed by the caller (the settings' preview card plays it inside its sketch, smaller): the
-- caller's place, and it opens; the menu's preview afterwards is full size again
local placedPanel
panel.SetScale = function(self, s) self.scale = s end
Case.ShowPreview(anchor, "frost", function(p)
  placedPanel = p
  p:SetScale(0.72)
end)
check(placedPanel == panel and panel.shown and pfx.phase == "opening" and pfx.styleID == "frost", "preview: placed by its caller, it opens")
Case.HidePreview()
RunPreview(0.1)
Case.ShowPreview(anchor, "vault")
check(panel.shown and (panel.scale or 1) == 1, "preview: beside the menu at full size again, scale " .. tostring(panel.scale))
Case.HidePreview()
RunPreview(0.1)
vaultShown = true

-- a style that fails mid-way: its slot is put to rest, the error is noted, nothing keeps running
Case.AddStyle({ id = "broken", name = "Broken" }, {
  openFor = 0.5,
  closeFor = 0.5,
  Enter = function() end,
  Update = function() error("a broken style") end,
  Rest = function(f) Case.kit.RestCommon(f) end,
})
BetterGreatVaultDB.vaultStyle = "broken"
hovering = true
Case.Open(slot)
Run(0.2)
local noted = BGV.errors[#BGV.errors]
check(noted and noted.label == "slot animation" and noted.message:find("a broken style"), "a failing style: its error is noted")
if noted and noted.message:find("a broken style") then table.remove(BGV.errors) end
hovering = false
AtRest("after a failing style")

-- The vault's rewards to choose from: a case opens on its own and stays open with the pointer
-- elsewhere; its reel stops with the reward at the marker, the reward grows, its name shows.
-- Collect shuts it; leaving opens it again onto the same reward, without spinning.
do
  local reward = { itemDBID = 77, itemID = 9999, icon = 7777 }
  C_WeeklyRewards = { GetItemHyperlink = function(id) return id == 77 and "|Hitem:9999::|h[Claim Blade]|h" or nil end }
  C_Item = {
    GetItemInfo = function(item) return "Claim Blade", item, 4 end,
    GetDetailedItemLevelInfo = function() return 285 end,
    GetItemQualityColor = function() return 0.64, 0.21, 0.93 end,
  }
  local claimStyles = {}
  for _, entry in ipairs(Case.STYLES) do if entry.id ~= "broken" then claimStyles[#claimStyles + 1] = entry.id end end
  check(#claimStyles >= 43, "every style gets a reward's reveal: " .. #claimStyles)
  for _, style in ipairs(claimStyles) do
    BetterGreatVaultDB.vaultStyle = style
    hovering = false
    Case.Stop(slot)
    Case.OpenClaim(slot, reward, ICONS)
    check(fx.phase == "opening", style .. ": a reward's case opens on its own")
    Run(1.5)
    check(fx.phase == "open", style .. ": held open with the pointer elsewhere: " .. fx.phase)
    Run(2.5)
    check(fx.landedAt ~= nil, style .. ": the reel stops")
    if style == "bandit" then
      -- its own three reels: each stops with the reward on the payline, and they stay
      for c, column in ipairs(fx.banditArt.columns) do
        local onLine
        for _, cell in ipairs(column.cells) do
          if cell.item == fx.claim then onLine = cell end
        end
        check(column.mode == "held" and onLine and onLine.icon.file == 7777, "bandit: reel " .. c .. " stops on the reward")
      end
      local landed = fx.landedAt
      Run(4)
      check(fx.landedAt == landed and fx.banditArt.columns[1].mode == "held", "bandit: the reels stay")
      check(fx.claimLabel and fx.claimLabel.shown and fx.claimLabel.name.text == "Claim Blade", "bandit: its name shows")
      Case.Stop(slot)
    else
    local marker = (fx.windowWidth or 213) / 2 + 1
    local at = fx.cursor + (marker - fx.offset) / 56 - 0.5
    check(math.abs(at - math.floor(at + 0.5)) < 0.01, style .. ": an item is centred on the marker: " .. at)
    check(math.floor(at + 0.5) == fx.landItem, style .. ": the reward is the item at the marker")
    local cell = fx.cells[fx.landItem - fx.cursor + 1]
    check(cell and cell.icon.file == 7777, style .. ": the cell at the marker shows the reward")
    check(cell and cell.icon.w and cell.icon.w >= 40 * 1.25 and cell.icon.w <= 56, style .. ": the reward grows, within its column: " .. tostring(cell and cell.icon.w))
    local other = fx.cells[1] ~= cell and fx.cells[1] or fx.cells[2]
    check(other.alpha < 0.5, style .. ": the other items dim")
    check(fx.claimLabel and fx.claimLabel.shown and fx.claimLabel.name.text == "Claim Blade", style .. ": its name shows")
    check(fx.claimLabel and fx.claimLabel.ilvl.text == "285 ilvl", style .. ": its item level shows")
    check(fx.marker.alpha == 0, style .. ": the marker fades")
    local offset, cursor = fx.offset, fx.cursor
    Run(1)
    check(fx.offset == offset and fx.cursor == cursor and fx.phase == "open", style .. ": and it stays")
    Run(5)
    check(fx.settled and not fx.driven and LiveTickers() == 0, style .. ": settled: no work a frame")
    Case.SuspendClaim(slot)
    Run(2)
    check(fx.phase == "closed" and fx.shown, style .. ": Collect: shut over the reward (" .. fx.phase .. ")")
    Case.ResumeClaim(slot)
    check(fx.phase == "opening", style .. ": left: it opens again")
    Run(1.5)
    check(fx.phase == "open" and fx.offset == offset and fx.cursor == cursor, style .. ": onto the same reward, without spinning")
    Run(3)
    check(fx.claimLabel.shown and fx.claimLabel.alpha == 1, style .. ": reopened: its name shows again (alpha " .. tostring(fx.claimLabel.alpha) .. ")")
    check(fx.settled, style .. ": and then it settles")
    Case.OpenClaim(slot, { itemDBID = 77, itemID = 9999, icon = 7777 }, ICONS)
    check(fx.phase == "open" and fx.landedAt ~= nil, style .. ": the same reward again changes nothing")
    Case.Stop(slot)
    check(fx.claim == nil and not fx.claimLabel.shown and fx.alpha == 1 and fx.marker.alpha == 1, style .. ": stopped: it lets go of the reward")
    end
  end
  -- Random: a reward's case keeps the style it was revealed with, closed for Collect and open again
  local function Centred()
    local marker = (fx.windowWidth or 213) / 2 + 1
    local at = fx.cursor + (marker - fx.offset) / 56 - 0.5
    return math.abs(at - math.floor(at + 0.5)) < 0.01 and math.floor(at + 0.5) == fx.landItem
  end
  BetterGreatVaultDB.vaultStyle = "random"
  for round = 1, 6 do
    Case.Stop(slot)
    Case.OpenClaim(slot, reward, ICONS)
    Run(4)
    local style, offset, cursor = fx.styleID, fx.offset, fx.cursor
    for _ = 1, 3 do
      Case.SuspendClaim(slot)
      Run(2.5)
      Case.ResumeClaim(slot)
      Run(3)
    end
    check(style == "broken" or fx.styleID == style, "random, round " .. round .. ": the same style when it opens again (" .. tostring(style) .. " -> " .. tostring(fx.styleID) .. ")")
    check(fx.offset == offset and fx.cursor == cursor, "random, round " .. round .. ": the reel where it landed")
    if style ~= "bandit" and style ~= "broken" then
      local marker = (fx.windowWidth or 213) / 2 + 1
      check(Centred(), "random, round " .. round .. ": the reward still at the marker (" .. tostring(style) .. ": at "
        .. tostring(fx.cursor + (marker - fx.offset) / 56 - 0.5) .. ", landItem " .. tostring(fx.landItem) .. ", landedAt " .. tostring(fx.landedAt) .. ", phase " .. fx.phase .. ")")
    end
  end
  -- revealed by the bandit's own reels, then open again in a style with the main reel: it lands
  BetterGreatVaultDB.vaultStyle = "bandit"
  Case.Stop(slot)
  Case.OpenClaim(slot, reward, ICONS)
  Run(5)
  check(fx.landedAt ~= nil and fx.landItem == nil, "the bandit revealed it on its own reels")
  fx.claimStyle, fx.claimStyleID = nil, nil -- as if the case had come back in another style
  BetterGreatVaultDB.vaultStyle = "classic"
  Case.SuspendClaim(slot)
  Run(2)
  Case.ResumeClaim(slot)
  Run(4)
  do
    local marker = (fx.windowWidth or 213) / 2 + 1
    check(fx.landItem ~= nil and Centred(), "then the main reel: it still lands on the reward (at " .. tostring(fx.cursor + (marker - fx.offset) / 56 - 0.5)
      .. ", landItem " .. tostring(fx.landItem) .. ", land " .. tostring(fx.land) .. ", phase " .. fx.phase .. ", style " .. tostring(fx.styleID) .. ")")
  end
  local cell = fx.landItem and fx.cells[fx.landItem - fx.cursor + 1]
  check(cell and cell.icon.file == 7777, "and the cell at the marker is the reward")
  -- Collect pointed at while it was still opening: it opens, then shuts; leaving opens it and it lands
  BetterGreatVaultDB.vaultStyle = "classic"
  Case.OpenClaim(slot, reward, ICONS)
  Run(0.2)
  Case.SuspendClaim(slot)
  Run(3)
  check(fx.phase == "closed" and fx.shown, "suspended while opening: shut in the end")
  Case.ResumeClaim(slot)
  Run(4)
  check(fx.landedAt ~= nil and fx.phase == "open", "resumed: it lands")
  -- a reward that hasn't loaded: shut, still, until it opens
  Case.Stop(slot)
  Case.Cover(slot)
  check(fx.shown and fx.phase == "closed" and LiveTickers() == 0, "covered: shut and still")
  Case.OpenClaim(slot, reward, ICONS)
  check(fx.phase == "opening", "covered, then opened")
  Case.Stop(slot)
  hovering = true
  Case.Open(slot)
  Run(1.5)
  check(fx.claim == nil and fx.landedAt == nil and fx.marker.alpha == 1, "a hover after a reward: an ordinary case")
  hovering = false
  Run(2)
  AtRest("after the rewards")
end

-- Away from the vault once the rewards are rolled: a reward shown as the reveal leaves it, at once
-- and still (Case.ShowClaims). Every style ends open on the reward with its name under it and
-- nothing running; the work is done in that one frame, and stays bounded.
do
  local reward = { itemDBID = 78, itemID = 9999, icon = 7777 }
  C_WeeklyRewards = { GetItemHyperlink = function() return "|Hitem:9999::|h[Claim Blade]|h" end }
  C_Item = {
    GetItemInfo = function(item) return "Claim Blade", item, 4 end,
    GetDetailedItemLevelInfo = function() return 285 end,
    GetItemQualityColor = function() return 0.64, 0.21, 0.93 end,
  }
  hovering = false
  local costs, worst = {}, 0
  for _, entry in ipairs(Case.STYLES) do
    local style = entry.id
    if style ~= "broken" then
      BetterGreatVaultDB.vaultStyle = style
      Case.Stop(slot)
      local before = calls
      Case.ShowClaims({ { frame = slot, reward = reward, icons = ICONS } })
      local cost = calls - before
      worst = math.max(worst, cost)
      costs[#costs + 1] = style .. " " .. cost
      check(fx.phase == "open" and fx.settled and not fx.driven and LiveTickers() == 0, style .. ": away: open and still at once (" .. fx.phase .. ")")
      check(fx.landedAt ~= nil, style .. ": away: on the reward")
      check(fx.claimLabel and fx.claimLabel.shown and fx.claimLabel.alpha == 1 and fx.claimLabel.name.text == "Claim Blade",
        style .. ": away: its name under it")
      if style ~= "bandit" then
        local cell = fx.landItem and fx.cells[fx.landItem - fx.cursor + 1]
        check(cell and cell.icon.file == 7777 and cell.icon.w >= 40 * 1.25, style .. ": away: the reward at the marker, grown")
      end
      check(LiveParticles() == 0, style .. ": away: nothing in the air")
      Case.ShowClaims({ { frame = slot, reward = reward, icons = ICONS } })
      check(fx.settled and LiveTickers() == 0, style .. ": away: shown again, it stays as it is")
    end
  end
  print("away, the reveal played in one go (calls):", table.concat(costs, ", "))
  check(worst < 20000, "away: the one-frame work stays bounded: " .. worst)
  -- the name not loaded yet: landed, it waits for it in real time, and settles once it's in
  local nameReady = false
  C_Item.GetItemInfo = function(item) if not nameReady then return nil end return "Claim Blade", item, 4 end
  BetterGreatVaultDB.vaultStyle = "classic"
  Case.Stop(slot)
  reward = { itemDBID = 79, itemID = 9999, icon = 7777 } -- a reward the game hasn't named yet
  Case.ShowClaims({ { frame = slot, reward = reward, icons = ICONS } })
  check(fx.landedAt and not fx.settled and LiveTickers() == 1 and not fx.claimLabel.shown, "away, the name loading: landed, waiting")
  nameReady = true
  Run(0.5)
  check(fx.claimLabel.shown, "away: its name once it has loaded")
  Run(3)
  check(fx.settled and LiveTickers() == 0, "away: then still")
  Case.Stop(slot)
end

-- A reward's case after it has settled, given another reward: it wakes, spins and lands on it.
-- A style that fails while it reveals a reward: the case opens again in Classic, the reward shown.
-- A style whose Enter fails: noted, and no error reaches the caller.
do
  local first = { itemDBID = 90, itemID = 9999, icon = 7777 }
  C_WeeklyRewards = { GetItemHyperlink = function() return "|Hitem:9999::|h[Claim Blade]|h" end }
  C_Item = {
    GetItemInfo = function(item) return "Claim Blade", item, 4 end,
    GetDetailedItemLevelInfo = function() return 285 end,
    GetItemQualityColor = function() return 0.64, 0.21, 0.93 end,
  }
  hovering = false
  BetterGreatVaultDB.vaultStyle = "classic"
  Case.Stop(slot)
  Case.OpenClaim(slot, first, ICONS)
  Run(7)
  check(fx.settled and LiveTickers() == 0, "settled on its reward")
  local other = { itemDBID = 91, itemID = 9998, icon = 7788 }
  Case.OpenClaim(slot, other, ICONS)
  check(LiveTickers() == 1 and not fx.settled, "another reward: the settled case wakes")
  Run(7)
  local cell = fx.landItem and fx.cells[fx.landItem - fx.cursor + 1]
  check(fx.claim == other and fx.landedAt and cell and cell.icon.file == 7788, "and lands on the new reward")
  check(fx.settled and LiveTickers() == 0, "and settles again")
  Case.Stop(slot)

  BetterGreatVaultDB.vaultStyle = "broken"
  Case.OpenClaim(slot, first, ICONS)
  Run(0.2)
  local noted = BGV.errors[#BGV.errors]
  check(noted and noted.message:find("a broken style", 1, true), "a style failing in a reveal: noted")
  if noted and noted.message:find("a broken style", 1, true) then table.remove(BGV.errors) end
  check(fx.claim == first and fx.styleID == "classic" and fx.phase ~= "closed", "the reward's case opens again in Classic: " .. tostring(fx.styleID))
  Run(7)
  check(fx.landedAt and fx.settled, "and shows the reward")
  Case.Stop(slot)

  Case.AddStyle({ id = "brokenEnter", name = "Broken Enter" }, {
    openFor = 0.5,
    closeFor = 0.5,
    Enter = function() error("a broken enter") end,
    Update = function() end,
    Rest = function(f) Case.kit.RestCommon(f) end,
  })
  BetterGreatVaultDB.vaultStyle = "brokenEnter"
  hovering = true
  local ok = pcall(Case.Open, slot)
  noted = BGV.errors[#BGV.errors]
  check(ok and noted and noted.message:find("a broken enter", 1, true), "a style whose Enter fails: noted, nothing thrown")
  if noted and noted.message:find("a broken enter", 1, true) then table.remove(BGV.errors) end
  hovering = false
  Run(2.5)
  AtRest("after a failing Enter")
end

-- The styles that open a hole keep the gates shut under the reel, which shows only in its window,
-- so the hole goes through the gates as well: each gate's face masked by the hole's inverse, sized
-- and placed with the hole, and nothing of them is left round the reel once open. Demonic Gateway
-- pulls its gates in under the reel itself; the other styles have no hole.
do
  local CUT = { cartoon = true, blood = true, devourer = true, shadow = true, affliction = true, fire = true,
    holypriest = true, balance = true }
  local function Cut(gate)
    local n, mask = 0, nil
    for m in pairs(gate.face.masks) do n, mask = n + 1, m end
    return n, mask
  end
  local function Checked(id, when)
    local nTop, top = Cut(fx.topDoor)
    local nBottom, bottom = Cut(fx.bottomDoor)
    if not CUT[id] then
      check(nTop == 0 and nBottom == 0, id .. ", " .. when .. ": the gates aren't cut")
      return
    end
    check(nTop == 1 and nBottom == 1 and top ~= bottom and top._parent == fx.topDoor and bottom._parent == fx.bottomDoor,
      id .. ", " .. when .. ": each gate is cut by a mask of its own")
    if not (top and bottom) then return end
    local circle = fx.circleFile:find("TempPortraitAlphaMask", 1, true) ~= nil
    local file = circle and Case.kit.MEDIA .. "CaseCircleCut" or fx.circleFile .. "Cut"
    local scale = circle and 64 / 60 or 1
    check(top.file == file and bottom.file == file and top.wrap == "CLAMPTOWHITE" and bottom.wrap == "CLAMPTOWHITE",
      id .. ", " .. when .. ": by the hole's inverse, whole outside it: " .. tostring(top.file))
    check(math.abs(top.w - fx.circle.w * scale) < 1e-6 and math.abs(top.h - fx.circle.h * scale) < 1e-6
      and bottom.w == top.w and bottom.h == top.h, id .. ", " .. when .. ": sized with the hole")
  end
  local cut = {}
  hovering = false
  for _, entry in ipairs(Case.STYLES) do
    local id = entry.id
    if not id:find("^broken") then
      BetterGreatVaultDB.vaultStyle = id
      hovering = true
      Case.Open(slot)
      Run(0.3)
      Checked(id, "opening")
      Run(1.2)
      check(fx.phase == "open", id .. ": open")
      Checked(id, "open")
      if CUT[id] then
        cut[#cut + 1] = id
        -- open: the hole (and its cut) well past the slot's corners
        local w, h = fx.slotWidth, fx.slotHeight
        check(fx.circle.w > w and fx.circle.h > h, id .. ": open past the slot: " .. fx.circle.w .. " x " .. fx.circle.h)
      end
      hovering = false
      Run(2.5)
      AtRest(id .. ", after its hole")
    end
  end
  check(#cut == 8, "eight styles cut their hole through the gates: " .. table.concat(cut, ","))

  -- a reward's case: cut while it's open, whole once shut for Collect, cut again when it opens
  BetterGreatVaultDB.vaultStyle = "blood"
  Case.Stop(slot)
  Case.OpenClaim(slot, { itemDBID = 92, itemID = 9999, icon = 7777 }, ICONS)
  Run(5)
  check(fx.settled, "a reward in Bonestorm: settled")
  Checked("blood", "a reward, settled")
  Case.SuspendClaim(slot)
  Run(2.5)
  check(fx.phase == "closed" and next(fx.topDoor.face.masks) == nil and next(fx.bottomDoor.face.masks) == nil,
    "shut for Collect: the gates whole again")
  Case.ResumeClaim(slot)
  Run(5)
  Checked("blood", "a reward, open again")
  Case.Stop(slot)
  check(next(fx.topDoor.face.masks) == nil and next(fx.bottomDoor.face.masks) == nil, "stopped: the gates whole")

  -- a hole whose shape changes while it's cut: the cut follows it
  BetterGreatVaultDB.vaultStyle = "devourer"
  hovering = true
  Case.Open(slot)
  Run(0.3)
  Case.kit.MaskShape(fx, Case.kit.MEDIA .. "CaseRot")
  local topCut, bottomCut = fx.topDoor.cut, fx.bottomDoor.cut
  check(topCut and bottomCut and topCut.file == Case.kit.MEDIA .. "CaseRotCut" and bottomCut.file == Case.kit.MEDIA .. "CaseRotCut",
    "the shape changed while cut: the cut follows it")
  hovering = false
  Run(2.5)
  AtRest("after a changed shape")
  check(fx.circleFile:find("TempPortraitAlphaMask", 1, true) ~= nil, "at rest the hole is the circle again")
end

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  check(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end

print(fails == 0 and "case checks passed" or (fails .. " case checks failed"))
