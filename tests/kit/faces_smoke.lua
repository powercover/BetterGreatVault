-- Faces.lua: pointing at Collect turns the done slots' gates sad (the best reward's slot wailing),
-- leaving cheers them up and puts everything back, in the progress week and the claim week.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("FACES FAIL: " .. message) end end
local calls = 0

local METHODS
local FIELDS = { ItemFrame = true, Background = true, ModelScene = true, Threshold = true, Progress = true }
local function NOOP() calls = calls + 1 end
local frames = {}
local function Region(kind, parent)
  local r = { kind = kind, shown = true, alpha = 1, _parent = parent, children = {}, regions = {}, masks = {}, level = 1, scripts = {}, points = {} }
  return setmetatable(r, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") or FIELDS[k] then return nil end
    return METHODS[k] or NOOP
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
  SetPoint = function(self, point, rel, relPoint, x, y) calls = calls + 1; self.points[point] = { rel, relPoint, x, y } end,
  ClearAllPoints = function(self) calls = calls + 1; self.points = {} end,
  GetCenter = function(self) return self.cx or 0, self.cy or 0 end,
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
  SetTexture = function(self, file) calls = calls + 1; self.file = file end,
  GetTexture = function(self) return self.file end,
  SetAtlas = function(self, a) calls = calls + 1; self.atlas = a end,
  GetAtlas = function(self) return self.atlas end,
  SetVertexColor = function(self, r, g, b) calls = calls + 1; self.color = { r, g, b } end,
  SetDesaturated = function(self, v) calls = calls + 1; self.grey = v end,
  SetRotation = function(self, r) calls = calls + 1; self.rotation = r end,
  SetTexCoord = function(self, ...) calls = calls + 1; self.coords = { ... } end,
  SetScript = function(self, name, fn) self.scripts[name] = fn end,
  HookScript = function(self, name, fn)
    local old = self.scripts[name]
    self.scripts[name] = function(...) if old then old(...) end fn(...) end
  end,
  GetScript = function(self, name) return self.scripts[name] end,
  GetParent = function(self) return self._parent end,
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
  frames[#frames + 1] = f
  return f
end

local clock = 100
function GetTime() return clock end
C_Timer = { After = function(_, fn) fn() end }
function debugprofilestop() return os.clock() * 1000 end
function GetLocale() return "enUS" end
UIParent = Region("Frame")
GameTooltip = Region("GameTooltip")
BetterGreatVaultDB = {}
function GetSpecialization() return 1 end
function GetSpecializationInfo() return 71 end
function GetLootSpecialization() return 0 end
Enum = { WeeklyRewardChestThresholdType = { Raid = 3, Activities = 1, World = 6, Concession = 9 }, CachedRewardType = { Item = 1, Currency = 2 } }
local LINKS, LEVELS = {}, {}
C_WeeklyRewards = { GetItemHyperlink = function(db) return LINKS[db] end }
C_Item = { GetDetailedItemLevelInfo = function(link) return LEVELS[link] end }

local BGV = {}
for _, path in ipairs({ "Locales/Locales.lua", "Utils.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end
local TIERS = {}
BGV.Bis = { Tier = function(itemID) return TIERS[itemID] end }
local progressWeek = true
BGV.Rewards = { PossibleIcons = function() return {}, false end, ShowingWeeklyProgress = function() return progressWeek end }
for _, path in ipairs({ "Case.lua", "CaseStyles.lua", FACES_PATH or "Faces.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end
local Case, Faces = BGV.Case, BGV.Faces
local caseDriver = UIParent.children[#UIParent.children]

-- the vault: three rows of three slots, Collect below them
local vaultShown = true
local vault = CreateFrame("Frame", "WeeklyRewardsFrame", UIParent)
vault.IsShown = function() return vaultShown end
vault.Activities = {}
vault.ConcessionsFrame = CreateFrame("Frame", nil, vault)
local rewards = CreateFrame("Frame", nil, vault.ConcessionsFrame)
vault.ConcessionsFrame.Rewards = rewards
local collect = CreateFrame("Frame", nil, rewards)
collect.type = Enum.WeeklyRewardChestThresholdType.Concession
collect.cx, collect.cy = 600, 60
rewards.ConcessionFrame1 = collect
table.insert(vault.Activities, collect)
local slots = {}
for row = 1, 3 do
  for col = 1, 3 do
    local slot = CreateFrame("Frame", nil, vault)
    slot.w, slot.h, slot.level = 219, 126, 200
    slot.cx, slot.cy = 300 + col * 230, 600 - row * 140
    slot.type, slot.index = row, col
    slot.bgvText = CreateFrame("Frame", nil, slot)
    slot.bgvHit = CreateFrame("Button", nil, slot)
    slots[#slots + 1] = slot
    table.insert(vault.Activities, slot)
  end
end
Faces.Hook(vault)
check(collect.scripts.OnEnter and collect.scripts.OnLeave, "Collect is hooked: pointing at it and leaving it")

local function FaceDriver()
  for _, f in ipairs(frames) do
    if f._parent == nil and f.scripts.OnUpdate and f ~= caseDriver then return f end
  end
end
local function Run(seconds)
  for _ = 1, math.floor(seconds * 60 + 0.5) do
    clock = clock + 1 / 60
    local d = FaceDriver()
    if d then d.scripts.OnUpdate(d, 1 / 60) end
    if caseDriver.scripts.OnUpdate then caseDriver.scripts.OnUpdate(caseDriver, 1 / 60) end
  end
end
local function Shown(face)
  local n = 0
  for _, texture in ipairs(face.all) do if texture.shown then n = n + 1 end end
  return n
end
-- Where the gates are anchored (nil: not anchored at all).
local function Offset(fx)
  local p = fx.points.TOPLEFT
  if not p then return nil, nil end
  return p[3], p[4]
end

-- --- the progress week: the addon's gates, five slots done ---------------------------------------------------
local LEVEL = { 282, 289, 0, 295, 285, 0, 289, 0, 0 } -- 0: not done
for i, slot in ipairs(slots) do
  slot.bgvSlot = { unlocked = LEVEL[i] > 0, itemLevel = LEVEL[i] > 0 and LEVEL[i] or nil }
  Case.Ensure(slot)
  Case.Rest(slot)
end
collect.scripts.OnEnter(collect)
Run(0.8)
local done = {}
for i, slot in ipairs(slots) do
  local face = slot.bgvFace
  if LEVEL[i] > 0 then
    done[#done + 1] = slot
    check(face and face.active and face.layer.shown, "slot " .. i .. " (done) has a face")
    check(face and Shown(face) >= 5, "slot " .. i .. ": its eyes, brows and mouth show: " .. (face and Shown(face) or 0))
    check(face and face.layer.level > slot.bgvFX.topDoor.level, "slot " .. i .. ": the face is over its gates")
    check(slot.bgvText.bgvFadeTarget == 0, "slot " .. i .. ": its caption fades")
  else
    check(not face or not face.active, "slot " .. i .. " (not done) has no face")
  end
end
check(slots[4].bgvFace.moodName == "wail", "the best reward's slot (295) wails: " .. tostring(slots[4].bgvFace.moodName))
check(slots[1].bgvFace.moodName == "sulk", "the least reward's slot (282) sulks: " .. tostring(slots[1].bgvFace.moodName))
local middle = {}
for _, i in ipairs({ 2, 5, 7 }) do middle[slots[i].bgvFace.moodName] = true end
check(middle.cry and middle.plead and middle.sad, "the others cry, plead and are sad")
-- each face behaves as it should: the hardest-hit shuts its eyes and cries from both, the crying one
-- sheds tears from one eye
local wail = slots[4].bgvFace
check(wail.eyes[1].kind == "shut" and wail.eyes[2].kind == "shut", "wailing: eyes shut")
check(slots[1].bgvFace.eyes[1].kind == "lid", "sulking: half-lidded eyes")
local sides = {}
for _ = 1, 120 do
  Run(1 / 60)
  for _, tear in ipairs(wail.tears) do if tear.live then sides[tear.x < 0 and "left" or "right"] = true end end
end
check(sides.left and sides.right, "wailing: tears from both eyes")
local crying
for _, slot in ipairs(done) do if slot.bgvFace.moodName == "cry" then crying = slot.bgvFace end end
local tears = 0
for _ = 1, 90 do
  Run(1 / 60)
  for _, tear in ipairs(crying.tears) do if tear.live then tears = tears + 1 break end end
end
check(tears > 20, "crying: tears roll down")
local moved = false
for _ = 1, 90 do Run(1 / 60); local _, y = Offset(wail.fx); if y and y < -2.2 then moved = true end end
check(moved, "wailing: the slot dips with each sob")
-- a blink closes the eyes for a moment, on every open-eyed face
local tallest, shortest = 0, math.huge
for _ = 1, 400 do
  Run(1 / 60)
  local eye = crying.eyes[1].texture
  if eye.shown and eye.h then tallest, shortest = math.max(tallest, eye.h), math.min(shortest, eye.h) end
end
check(shortest < tallest * 0.4, "crying: it blinks: " .. shortest .. " of " .. tallest)
-- held: little work a frame for five faces
local before = calls
Run(1)
local perFrame = (calls - before) / 60
print(string.format("work a frame while held, five faces: %.1f calls", perFrame))
check(perFrame < 80, "held faces cost little: " .. perFrame)

-- leaving Collect: a moment of relief, then everything as it was
collect.scripts.OnLeave(collect)
Run(0.2)
check(wail.relief > 0.5 and wail.eyes[1].kind == "content", "leaving: they smile with relief")
Run(0.25)
check(wail.show < 1 and wail.show > 0 and wail.eyes[1].kind == "content" and crying.eyes[1].kind == "content",
  "fading away: still smiling, eyes content: " .. tostring(wail.show) .. " " .. tostring(crying.eyes[1].kind))
Run(1)
for i, slot in ipairs(done) do
  local face = slot.bgvFace
  local x, y = Offset(slot.bgvFX)
  check(not face.active and not face.layer.shown and Shown(face) == 0, "slot " .. i .. ": the face is gone")
  check(x == 0 and y == 0, "slot " .. i .. ": the gates are back in place")
  check(slot.bgvText.bgvFadeTarget == 1, "slot " .. i .. ": the caption is back")
  check(slot.bgvFX.topDoor.shown and slot.bgvFX.topDoor.h == 63, "slot " .. i .. ": the gates are shut, as at rest")
end
check(not Faces.IsShowing() and FaceDriver() == nil, "nothing left running")

-- pointed at again while cheering up: back to sad, no restart
collect.scripts.OnEnter(collect)
Run(0.6)
collect.scripts.OnLeave(collect)
Run(0.15)
collect.scripts.OnEnter(collect)
Run(0.5)
check(wail.active and wail.entering and wail.sad > 0.9 and wail.relief < 0.1, "pointed at again: sad again")
collect.scripts.OnLeave(collect)
Run(1.5)
check(not Faces.IsShowing(), "and gone after leaving")

-- a slot opened while its face cheers up: the face goes at once, and the open case keeps its caption
collect.scripts.OnEnter(collect)
Run(0.6)
collect.scripts.OnLeave(collect)
Run(0.1)
local opened = slots[5]
function GetMouseFoci() return { opened.bgvHit } end
BetterGreatVaultDB.vaultStyle = "classic" -- a style that doesn't shake the case
-- the faces must not bring the caption back over the open case, not even for a frame
local realFade = Case.FadeCaption
local captionOverCase = false
Case.FadeCaption = function(frame, alpha)
  if frame == opened and alpha == 1 and Case.IsAnimating(opened) then captionOverCase = true end
  return realFade(frame, alpha)
end
Case.Open(opened)
Run(0.3)
Case.FadeCaption = realFade
check(not captionOverCase, "opened while cheering up: the caption never comes back over the open case")
check(not opened.bgvFace.active and not opened.bgvFace.layer.shown, "opened while cheering up: its face is gone")
check(opened.bgvText.bgvFadeTarget == 0, "opened while cheering up: the open case keeps the caption faded")
local ox, oy = Offset(opened.bgvFX)
check(ox == 0 and oy == 0, "opened while cheering up: the case is in place")
function GetMouseFoci() return { UIParent } end
Run(3)
check(not Faces.IsShowing() and opened.bgvText.bgvFadeTarget == 1, "and once it closes, all is back")
BetterGreatVaultDB.vaultStyle = nil

-- a slot whose case is open gets no face
local hovered = slots[2]
function GetMouseFoci() return { hovered.bgvHit } end
Case.Open(hovered)
collect.scripts.OnEnter(collect)
check(not (hovered.bgvFace and hovered.bgvFace.layer.shown), "an open slot gets no face, not even for a frame")
Run(0.3)
check(not (hovered.bgvFace and hovered.bgvFace.active), "an open slot keeps its reel, no face")
collect.scripts.OnLeave(collect)
function GetMouseFoci() return { UIParent } end
Run(3)

-- pointed at Collect while a slot's gates are still opening or closing: that slot cries too, once its
-- gates are shut, if Collect is still pointed at; and it keeps its place in the ranking
BetterGreatVaultDB.vaultStyle = "vault" -- finishes opening before it closes
local busy = slots[4] -- the best reward (295): it will wail
function GetMouseFoci() return { busy.bgvHit } end
Case.Open(busy)
Run(0.2)
function GetMouseFoci() return { UIParent } end
collect.scripts.OnEnter(collect)
check(Case.IsAnimating(busy) and not (busy.bgvFace and busy.bgvFace.active), "a busy slot: no face while its gates move")
check(slots[1].bgvFace.active and slots[1].bgvFace.moodName == "sulk", "the others get their faces at once")
local wailing = 0
for _, slot in ipairs(slots) do if slot ~= busy and slot.bgvFace and slot.bgvFace.active and slot.bgvFace.moodName == "wail" then wailing = wailing + 1 end end
check(wailing == 0, "no one else takes the busy slot's place: it is still the one to wail")
Run(1.3) -- Vault Door: 0.62 s opening, then 0.5 s closing
check(not Case.IsAnimating(busy) and busy.bgvFace and busy.bgvFace.active and busy.bgvFace.moodName == "wail",
  "its gates shut: the busy slot cries too, wailing: " .. tostring(busy.bgvFace and busy.bgvFace.moodName))
Run(0.5)
check(busy.bgvFace.layer.shown and busy.bgvFace.show > 0.9 and busy.bgvText.bgvFadeTarget == 0, "its face is up, its caption faded")
collect.scripts.OnLeave(collect)
Run(1.5)
check(not Faces.IsShowing() and FaceDriver() == nil, "leaving: all of them go, nothing left running")

-- left before the gates shut: the busy slot gets no face, and nothing waits on
function GetMouseFoci() return { busy.bgvHit } end
Case.Open(busy)
Run(0.2)
function GetMouseFoci() return { UIParent } end
collect.scripts.OnEnter(collect)
Run(0.1)
collect.scripts.OnLeave(collect)
Run(3)
check(not busy.bgvFace.active and not busy.bgvFace.layer.shown, "left before the gates shut: no face for the busy slot")
check(not Faces.IsShowing() and FaceDriver() == nil, "left before the gates shut: nothing left running")
check(busy.bgvText.bgvFadeTarget == 1, "left before the gates shut: its caption is back")

-- only the busy slot is done: nothing to show yet, but the face still comes once its gates shut
local saved = {}
for i, slot in ipairs(slots) do saved[i] = slot.bgvSlot.unlocked; slot.bgvSlot.unlocked = (slot == busy) end
function GetMouseFoci() return { busy.bgvHit } end
Case.Open(busy)
Run(0.2)
function GetMouseFoci() return { UIParent } end
collect.scripts.OnEnter(collect)
check(not Faces.IsShowing() and FaceDriver() ~= nil, "the only done slot is busy: no faces yet, but waiting on it")
Run(1.2)
check(busy.bgvFace.active and busy.bgvFace.moodName == "wail", "the only done slot: it wails once its gates are shut")
collect.scripts.OnLeave(collect)
Run(1.5)
check(not Faces.IsShowing() and FaceDriver() == nil, "and all is quiet after leaving")
for i, slot in ipairs(slots) do slot.bgvSlot.unlocked = saved[i] end
BetterGreatVaultDB.vaultStyle = nil

-- a face that fails goes (its gates and caption back), the error is noted, and the others go on
collect.scripts.OnEnter(collect)
Run(0.5)
local broken = slots[1].bgvFace
broken.mood = {} -- nothing to draw it with: its next frame fails
Run(0.1)
local lastError = BGV.errors[#BGV.errors]
check(not broken.layer.shown and lastError and lastError.label == "sad gates", "a failing face goes, its error noted: " .. tostring(lastError and lastError.message))
if lastError and lastError.label == "sad gates" then table.remove(BGV.errors) end
check(slots[1].bgvText.bgvFadeTarget == 1, "a failing face: its caption comes back")
check(slots[4].bgvFace.active and slots[4].bgvFace.layer.shown, "a failing face: the others go on")
collect.scripts.OnLeave(collect)
Run(1.5)
check(not Faces.IsShowing() and FaceDriver() == nil, "a failing face: all quiet after leaving")

-- the vault closes: every face goes at once
collect.scripts.OnEnter(collect)
Run(0.5)
Faces.Stop()
check(not Faces.IsShowing() and FaceDriver() == nil and not slots[4].bgvFace.layer.shown, "vault closed: faces gone at once")
local x, y = Offset(slots[4].bgvFX)
check(x == 0 and y == 0, "vault closed: gates back in place")

-- off in the settings, or with the slots not animated: nothing
BetterGreatVaultDB.disableCollectFaces = true
collect.scripts.OnEnter(collect)
Run(0.3)
check(not Faces.IsShowing(), "turned off: no faces")
collect.scripts.OnLeave(collect)
BetterGreatVaultDB.disableCollectFaces = nil
BetterGreatVaultDB.disableAnimations = true
collect.scripts.OnEnter(collect)
Run(0.3)
check(not Faces.IsShowing(), "slots not animated: no faces")
collect.scripts.OnLeave(collect)
BetterGreatVaultDB.disableAnimations = nil

-- --- the claim week: Blizzard's slots; gates close over the rewards while Collect is pointed at ---------------
progressWeek = false
for i, slot in ipairs(slots) do
  slot.bgvSlot = nil
  Case.Stop(slot)
  slot.hasRewards = i <= 3
  slot.info = { rewards = { { type = Enum.CachedRewardType.Item, id = 8000 + i, itemDBID = "db" .. i } } }
  LINKS["db" .. i] = "link" .. i
end
-- the vault's glow scene, which the slots sit under in the claim week
vault.ModelScene = CreateFrame("Frame", nil, vault)
vault.ModelScene.level = 300
for _, slot in ipairs(slots) do slot.level, slot.bgvBaseLevel = 200, nil end
-- slot 2 holds an S-tier item at a lower level than slot 1's A-tier one: the S tier counts first
TIERS[8001], TIERS[8002], TIERS[8003] = "A", "S", nil
LEVELS.link1, LEVELS.link2, LEVELS.link3 = 298, 285, 302
check(not slots[1].bgvFX.topDoor.shown, "claim week: no gates before Collect is pointed at")
collect.scripts.OnEnter(collect)
Run(0.8)
check(slots[2].bgvFace.moodName == "wail", "claim week: the S-tier item's slot wails: " .. tostring(slots[2].bgvFace.moodName))
check(slots[3].bgvFace.moodName == "sulk", "claim week: the item of no tier sulks: " .. tostring(slots[3].bgvFace.moodName))
for i = 1, 3 do
  local fx = slots[i].bgvFX
  check(fx.topDoor.shown and fx.bottomDoor.shown and fx.topDoor.h >= 62, "claim week slot " .. i .. ": the gates closed over the reward")
end
check(not (slots[4].bgvFace and slots[4].bgvFace.active), "claim week: a slot without a reward has no face")
check(slots[1].level > 300 and slots[2].level > 300, "claim week: the slots rise above the vault's glow: " .. slots[1].level)
collect.scripts.OnLeave(collect)
Run(1.5)
for i = 1, 3 do
  local fx = slots[i].bgvFX
  check(not fx.topDoor.shown and not fx.bottomDoor.shown and not slots[i].bgvFace.layer.shown, "claim week slot " .. i .. ": back to Blizzard's slot")
  check(slots[i].level == 200, "claim week slot " .. i .. ": back at its own level: " .. slots[i].level)
end
check(not Faces.IsShowing() and FaceDriver() == nil, "claim week: nothing left running")

-- --- the claim week with the rewards revealed: each slot's case is open onto its reward --------------------
-- Collect pointed at: the cases close, the faces form on their shut gates; left: the cases open
-- again onto the same rewards, without spinning.
local REEL = {}
for i = 1, 8 do REEL[i] = { icon = 7000 + i, itemID = 8100 + i } end
for i = 1, 3 do
  Case.OpenClaim(slots[i], { itemDBID = "db" .. i, itemID = 8000 + i, icon = 6000 + i }, REEL)
end
Run(4)
local landed = {}
for i = 1, 3 do
  local fx = slots[i].bgvFX
  check(fx.phase == "open" and fx.landedAt ~= nil, "revealed slot " .. i .. ": open onto its reward")
  landed[i] = { offset = fx.offset, cursor = fx.cursor }
end
collect.scripts.OnEnter(collect)
Run(0.1)
for i = 1, 3 do
  check(slots[i].bgvFX.phase == "closing", "revealed slot " .. i .. ": Collect pointed at: it closes")
end
-- frame by frame: once a case has shut, its gates never open again under the face
local gap = false
for _ = 1, 120 do
  Run(1 / 60)
  for i = 1, 3 do
    local fx = slots[i].bgvFX
    if (fx.phase == "closed" or fx.phase == "tail") and not (fx.topDoor.shown and (fx.topDoor.h or 0) >= 62) then gap = true end
  end
end
check(not gap, "revealed: the gates stay shut from the case closing to the face forming")
for i = 1, 3 do
  local fx, face = slots[i].bgvFX, slots[i].bgvFace
  check(fx.phase == "closed" and fx.shown, "revealed slot " .. i .. ": shut over its reward")
  check(face and face.active and face.handBack and face.gate == 1, "revealed slot " .. i .. ": its face forms on the shut gates")
  check(fx.topDoor.shown and fx.topDoor.h >= 62, "revealed slot " .. i .. ": the gates stay shut under the face")
end
check(slots[2].bgvFace.moodName == "wail", "revealed: the S-tier item's slot wails")
collect.scripts.OnLeave(collect)
Run(0.6)
for i = 1, 3 do
  check(slots[i].bgvFX.phase == "opening" or slots[i].bgvFX.phase == "open", "revealed slot " .. i .. ": left: it opens again (" .. slots[i].bgvFX.phase .. ")")
end
Run(2)
for i = 1, 3 do
  local fx = slots[i].bgvFX
  check(fx.phase == "open" and fx.offset == landed[i].offset and fx.cursor == landed[i].cursor, "revealed slot " .. i .. ": onto the same reward, without spinning")
  check(not slots[i].bgvFace.active, "revealed slot " .. i .. ": its face is gone")
end
check(not Faces.IsShowing() and FaceDriver() == nil, "revealed: nothing left running for the faces")
-- pointed at and left again before the gates had shut: they open again without a face
collect.scripts.OnEnter(collect)
Run(0.1)
collect.scripts.OnLeave(collect)
Run(3)
for i = 1, 3 do
  local fx = slots[i].bgvFX
  check(fx.phase == "open" and fx.offset == landed[i].offset, "revealed slot " .. i .. ": a quick pass over Collect: open again")
end
-- the vault closing while the faces show: everything stops, nothing reopens
collect.scripts.OnEnter(collect)
Run(2)
Faces.Stop()
for i = 1, 3 do
  check(slots[i].bgvFX.phase == "closed", "revealed slot " .. i .. ": the vault closing doesn't open it again")
end
for i = 1, 3 do Case.Stop(slots[i]) end
Run(1)
for i = 1, 3 do
  check(slots[i].bgvFX.phase == "closed" and not slots[i].bgvFX.shown and not Case.HasClaim(slots[i]), "revealed slot " .. i .. ": the vault closed: all stopped")
end
check(not Faces.IsShowing() and FaceDriver() == nil, "revealed: nothing left running at the end")

-- --- the claim week with a reward still loading: its slot is shut (Case.Cover) until they all open ----------
-- Collect pointed at: the face forms on the shut gates (they don't open first); left: the slot stays
-- shut, waiting for its reward
Case.Cover(slots[1])
local covered = slots[1].bgvFX
check(covered.shown and covered.topDoor.shown and covered.topDoor.h >= 62, "loading: shut")
collect.scripts.OnEnter(collect)
Run(0.05)
check(covered.topDoor.shown and covered.topDoor.h >= 62, "loading, Collect pointed at: the gates stay shut")
Run(0.8)
check(slots[1].bgvFace.active and slots[1].bgvFace.layer.shown, "and the face forms on them")
collect.scripts.OnLeave(collect)
Run(1.5)
check(covered.shown and covered.topDoor.shown and covered.topDoor.h >= 62 and not slots[1].bgvFace.layer.shown,
  "left: still shut, waiting for its reward")
Case.Stop(slots[1])
Run(0.5)
check(not Faces.IsShowing() and FaceDriver() == nil, "loading: nothing left running")

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  check(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end

print(fails == 0 and "faces checks passed" or (fails .. " faces checks failed"))
