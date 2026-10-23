-- The Great Vault overlay (UI.lua) with EllesmereUI's vault skin: its progress bar is hidden on
-- the addon's unlocked slots and shown again elsewhere, and the gates have no backing fill.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("VAULT UI FAIL: " .. message) end end

-- Blizzard's child keys on the vault's frames, which UI.lua reads as fields, not methods.
local FIELDS = {}
for _, key in ipairs({ "ItemFrame", "CompletedIcon", "CompletedActivityFlipbook", "ItemGlow", "UncollectedGlow",
    "RewardGenerated", "SheenAnim", "CompletedActivityAnim", "ModelScene", "Activities", "Background", "Threshold",
    "Progress", "FadeAnim" }) do
  FIELDS[key] = true
end
local function Widget(kind, parent)
  local w = { kind = kind, shown = true, children = {}, regions = {}, level = 1, scripts = {}, _parent = parent }
  return setmetatable(w, { __index = function(_, k)
    if type(k) ~= "string" or not k:match("^%u") or FIELDS[k] then return nil end
    if k == "IsShown" or k == "IsVisible" then return function(self) return self.shown end end
    if k == "Show" then return function(self) self.shown = true end end
    if k == "Hide" then return function(self) self.shown = false end end
    if k == "SetAlpha" then return function(self, a) self.alpha = a end end
    if k == "GetAlpha" then return function(self) return self.alpha or 1 end end
    if k == "SetShown" then return function(self, v) self.shown = v and true or false end end
    if k == "GetChildren" then return function(self) return unpack(self.children) end end
    if k == "GetRegions" then return function(self) return unpack(self.regions) end end
    if k == "CreateTexture" or k == "CreateFontString" then return function(self, _, layer)
      local r = Widget(k == "CreateTexture" and "Texture" or "FontString", self)
      r.layer = layer
      table.insert(self.regions, r)
      return r end end
    if k == "SetColorTexture" then return function(self, r, g, b, a) self.color = { r, g, b, a } end end
    if k == "SetAtlas" then return function(self, a) self.atlas = a end end
    if k == "GetAtlas" then return function(self) return self.atlas end end
    if k == "GetFrameLevel" then return function(self) return self.level end end
    if k == "SetFrameLevel" then return function(self, v) self.level = v end end
    if k == "GetHeight" then return function() return 120 end end
    if k == "GetWidth" then return function() return 160 end end
    if k == "GetStringHeight" then return function() return 12 end end
    if k == "GetParent" then return function(self) return self._parent end end
    if k == "SetParent" then return function(self, p) self._parent = p end end
    if k == "SetScript" then return function(self, name, fn) self.scripts[name] = fn end end
    if k == "HookScript" then return function(self, name, fn)
      local old = self.scripts[name]
      self.scripts[name] = function(...) if old then old(...) end fn(...) end end end
    if k == "IsMouseOver" then return function() return false end end
    if k == "SetText" then return function(self, t) self.text = t end end
    if k == "ClearAllPoints" then return function(self) self.points = {} end end
    if k == "SetPoint" then return function(self, ...)
      self.points = self.points or {}
      table.insert(self.points, { ... }) end end
    if k == "GetText" then return function(self) return self.text end end
    return function() end
  end })
end
function CreateFrame(kind, name, parent)
  local w = Widget(kind, parent)
  if parent then table.insert(parent.children, w) end
  if name then _G[name] = w end
  return w
end
function hooksecurefunc(target, name, fn)
  if type(target) == "string" then target, name, fn = _G, target, name end
  local original = target[name]
  target[name] = function(...)
    local results = { original(...) }
    fn(...)
    return unpack(results)
  end
end
local timers = {}
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
local function RunTimers()
  while #timers > 0 do
    local batch = timers
    timers = {}
    for _, fn in ipairs(batch) do fn() end
  end
end
function GetLocale() return "enUS" end
function IsModifiedClick() return false end
GameTooltip = Widget("GameTooltip")
BetterGreatVaultDB = {}
GameFontHighlightSmall, GameFontHighlight, GameFontNormal = Widget("Font"), Widget("Font"), Widget("Font")

-- the game's clock (a later block runs its own)
function GetTime() return 400 end
local BGV = {}
for _, path in ipairs({ "Locales/Locales.lua", "Utils.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end
BGV.GreatVault = {
  ProgressText = function(slot) return slot.unlocked and "285" or "2/4" end,
  DetailText = function() return nil end,
  Invalidate = function() end,
  GetSnapshot = function() return {} end,
  RequestRunData = function() end,
}
BGV.Rewards = {
  ResolveReward = function() end,
  PossibleIcons = function() return {}, false end,
  ShowingWeeklyProgress = function() return true end,
}
BGV.Tooltip = { ShowStandalone = function() end }
BGV.Bis = { Tier = function() return nil end }
-- the frames Case.lua makes as it loads: its ticker among them (CaseDriver, while a slot animates)
local caseFrames = {}
do
  local create = CreateFrame
  CreateFrame = function(...) local f = create(...) caseFrames[#caseFrames + 1] = f return f end
  assert(loadfile("Case.lua"))("BetterGreatVault", BGV)
  CreateFrame = create
end
local function CaseDriver()
  for _, f in ipairs(caseFrames) do
    if f.scripts.OnUpdate then return f end
  end
end
assert(loadfile("CaseStyles.lua"))("BetterGreatVault", BGV)
assert(loadfile("UI.lua"))("BetterGreatVault", BGV)
local UI = BGV.UI

-- A vault slot as EllesmereUI's skin leaves it: its card (tile, dark overlay and a border frame
-- inside) and its progress bar, marked like the skin's.
local vault = CreateFrame("Frame", "WeeklyRewardsFrame")
local function Slot()
  local slot = CreateFrame("Frame", nil, vault)
  slot.Background = slot:CreateTexture(nil, "BACKGROUND")
  slot.Background:SetAtlas("evergreen-weeklyrewards-reward-unlocked")
  slot.Threshold = slot:CreateFontString()
  slot.Progress = slot:CreateFontString()
  return slot
end
local function SkinBar(slot)
  local bar = CreateFrame("Frame", nil, slot)
  bar._euiTrack = bar:CreateTexture(nil, "BACKGROUND")
  bar._euiFill = bar:CreateTexture(nil, "ARTWORK")
  return bar
end
local function SkinCard(slot)
  local card = CreateFrame("Frame", nil, slot)
  card._euiBorderCreated = true
  CreateFrame("Frame", nil, card) -- its border strips
  card._euiTileBg = card:CreateTexture(nil, "BACKGROUND")
  card._euiDarkOverlay = card:CreateTexture(nil, "ARTWORK")
  return card
end
local function Seen(frame) return frame.shown and (frame.alpha or 1) > 0 end
local complete, locked = Slot(), Slot()
vault.Activities = { complete, locked }
local completeBar, lockedBar = SkinBar(complete), SkinBar(locked)
local completeCard, lockedCard = SkinCard(complete), SkinCard(locked)
local otherChild = CreateFrame("Frame", nil, complete)

UI.Apply(complete, { unlocked = true, source = {} })
UI.Apply(locked, { unlocked = false, source = {} })
do
  local open, shut = complete.bgvProgress.points[1], locked.bgvProgress.points[1]
  check(open and open[2] == complete and open[3] == "LEFT", "an unlocked slot's caption is in its middle")
  check(shut and shut[2] == locked and shut[3] == "TOPLEFT" and shut[5] <= -4 and shut[5] - 12 >= -48,
    "a locked slot's caption is in the band above the keyhole: " .. tostring(shut and shut[3]) .. " " .. tostring(shut and shut[5]))
end
check(not Seen(completeBar), "the skin's bar is gone from an unlocked slot")
check(not Seen(completeCard), "the skin's square card is gone from an unlocked slot")
check(Seen(lockedBar) and Seen(lockedCard), "a locked slot keeps the skin's card and progress bar")
check(Seen(otherChild) and otherChild.alpha == nil, "other frames of the slot are left alone")
completeCard:Show() -- the skin's next refresh shows its card again
check(not Seen(completeCard), "the card stays gone through the skin's refreshes")
UI.Clear(complete)
check(Seen(completeBar) and Seen(completeCard), "card and bar are back once the addon lets go of the slot")

-- The gates: no backing fill behind the doors, animated or still
local function Brown(frame)
  for _, region in ipairs(frame and frame.regions or {}) do
    if region.color and region.layer == "BACKGROUND" then return true end
  end
  return false
end
UI.Apply(complete, { unlocked = true, source = {} })
local fx = complete.bgvFX
check(fx and fx.topDoor and fx.bottomDoor, "the slot has its gates")
check(not complete.Background.shown and locked.Background.shown, "a completed slot's card is down under the gates; a locked slot keeps its own")
-- a skin that hid the card itself (EllesmereUI, on every slot and on Collect): the addon never shows it
do
  local skinned = Slot()
  skinned.Background:SetAlpha(0)
  UI.Apply(skinned, { unlocked = false, source = {} })
  UI.Clear(skinned)
  check(skinned.Background.alpha == 0 and skinned.Background.shown, "a card a skin hid stays as the skin left it on a slot the addon doesn't hold")
  UI.Apply(skinned, { unlocked = true, source = {} })
  check(not skinned.Background.shown and skinned.Background.alpha == 0, "the addon's slot: hidden, the skin's alpha left alone")
  UI.Clear(skinned)
  check(skinned.Background.shown and skinned.Background.alpha == 0, "let go: shown again, still as the skin left it")
end
check(not Brown(fx.topDoor) and not Brown(fx.bottomDoor), "no backing fill behind the animated gates")
check(fx.topDoor.backing == nil and fx.bottomDoor.backing == nil, "no backing textures on the animated gates")
BetterGreatVaultDB.disableAnimations = true
UI.Apply(complete, { unlocked = true, source = {} })
local closed = complete.bgvClosed
check(closed and closed.shown and closed.topDoor.face.atlas == "evergreen-weeklyrewards-reward-unlocked", "still gates show the slot's face")
check(not Brown(closed.topDoor) and not Brown(closed.bottomDoor) and closed.topDoor.backing == nil, "no backing fill behind the still gates")
BetterGreatVaultDB.disableAnimations = nil

-- The skin makes its card and bar a frame after the vault first shows: synced once that has run
-- Blizzard's vault: the frame copied its methods from the mixin when it was made, so only hooks on
-- the frame itself reach it. A show refreshes (FullRefresh); a refresh decides on the "unclaimed
-- rewards" box and dimming for rewards waiting away from the vault (UpdateOverlay), then
-- refreshes the slots (slotRefresh: what Blizzard's per-slot refresh does to their art).
WeeklyRewardsMixin = {
  OnShow = function(self) self:Refresh() end,
  Refresh = function(self)
    self:UpdateOverlay()
    for _, step in ipairs(self.slotRefresh or {}) do step() end
  end,
  UpdateOverlay = function(self) self.Overlay.shown = self.awayWithRewards == true end,
  OnHide = function() end,
}
local mixinRefresh = WeeklyRewardsMixin.Refresh
for name, method in pairs(WeeklyRewardsMixin) do vault[name] = method end
vault.level = 100
vault.Blackout = CreateFrame("Frame", nil, vault)
vault.Blackout.level = 1000
vault.Overlay = CreateFrame("Frame", nil, vault)
vault.Overlay.shown = false
local lootSpec, activeSpec = 0, 581
function GetLootSpecialization() return lootSpec end
function GetSpecialization() return 2 end
function GetSpecializationInfo() return activeSpec, "Vengeance" end
function GetSpecializationInfoByID(id) return id, ({ [581] = "Vengeance", [577] = "Havoc" })[id] end
-- the Collect buttons: one skinned by EllesmereUI (its inset square card), one as Blizzard's
vault.ConcessionsFrame = CreateFrame("Frame", nil, vault)
vault.ConcessionsFrame.Rewards = CreateFrame("Frame", nil, vault.ConcessionsFrame)
local function CollectButton(skinned)
  local b = CreateFrame("Frame", nil, vault.ConcessionsFrame.Rewards)
  b.level = 120
  b.SelectedTexture, b.UnselectedFrame = b:CreateTexture(), CreateFrame("Frame", nil, b)
  b.SetSelectionState = function(self, state)
    self.SelectedTexture:SetShown(state == 3)
    self.UnselectedFrame:SetShown(state == 2)
  end
  if skinned then
    b.SelectedTexture:SetAlpha(0) -- the skin strips Blizzard's golden frame
    b.card = CreateFrame("Frame", nil, b)
    b.card._euiBorderCreated = true
    b.card.level = 120
  end
  return b
end
local skinnedCollect, plainCollect = CollectButton(true), CollectButton(false)
UI.Hook()
check(WeeklyRewardsMixin.Refresh == mixinRefresh and vault.Refresh ~= mixinRefresh, "hooked on the vault frame, the mixin left alone")
-- EllesmereUI's square Collect buttons glow gold when selected; the default interface's keep Blizzard's own
skinnedCollect:SetSelectionState(3)
local collectGlow = skinnedCollect.bgvGlow
check(collectGlow and collectGlow.shown and collectGlow:GetParent() == skinnedCollect and collectGlow.level == 121,
  "a selected EllesmereUI Collect button: a golden glow on the skin's card, above it")
skinnedCollect:SetSelectionState(2)
check(not collectGlow.shown, "another selected: no glow")
skinnedCollect:SetSelectionState(3)
skinnedCollect:SetSelectionState(1)
check(not collectGlow.shown, "none selected: no glow")
plainCollect:SetSelectionState(3)
check(plainCollect.bgvGlow == nil and plainCollect.SelectedTexture.shown and (plainCollect.SelectedTexture.alpha or 1) == 1,
  "the default interface's Collect: Blizzard's own glow, nothing of the addon's")
local fresh = Slot()
vault.Activities = { fresh }
vault.shown = true
BGV.GreatVault.GetSnapshot = function() return { { type = 1, index = 1, unlocked = true, source = {} } } end
vault.GetActivityFrame = function() return fresh end
vault:OnShow()
check(fresh.bgvSlot and fresh.bgvSlot.unlocked, "the show applies the addon's slot")
local lateBar, lateCard = SkinBar(fresh), SkinCard(fresh) -- the skin's pass, a frame later
check(vault.bgvSkinQueued == true, "a sync queued for after the skin's pass")
local queued = #timers
vault:Refresh()
check(#timers == queued, "a refresh in the same frame doesn't queue another")
RunTimers()
check(not Seen(lateBar) and not Seen(lateCard), "card and bar made after the show are gone on an unlocked slot")
lateCard:Show()
vault:OnShow()
RunTimers()
check(not Seen(lateBar) and not Seen(lateCard) and vault.bgvSkinQueued == nil, "later shows keep them gone")

-- the reel preload: a step that fails ends the run (the error noted), so the next show starts it again
do
  local icons = BGV.Rewards.PossibleIcons
  BGV.Rewards.PossibleIcons = function() error("no icons") end
  vault.bgvPumping, vault.bgvContentQueued, vault.bgvPumpIndex = nil, nil, nil
  UI.ScheduleContent(vault)
  RunTimers()
  local noted = BGV.errors[#BGV.errors]
  check(vault.bgvPumping == nil and noted and noted.label == "reel preload", "a preload step that fails: the run ends, its error noted")
  if noted and noted.label == "reel preload" then table.remove(BGV.errors) end
  BGV.Rewards.PossibleIcons = icons
end

-- a slot the addon doesn't show any more (out of the vault's snapshot): all Blizzard's again
do
  local s = Slot()
  s.CompletedIcon = s:CreateTexture()
  UI.Apply(s, { unlocked = true, source = {} })
  check(s.bgvHit and s.bgvHit.shown and s.Threshold.alpha == 0, "applied: the addon's slot")
  UI.Clear(s)
  check(s.bgvSlot == nil and not s.bgvHit.shown and s.Threshold.shown and s.Threshold.alpha == 1 and s.CompletedIcon.alpha == 1,
    "cleared: Blizzard's captions seen again, nothing of the addon's over it")
end

-- Opened away from the vault with rewards waiting: the loot spec button above Blizzard's dimming,
-- and under its box the spec the rewards will be rolled for
local function Note() return vault.bgvAwayNote end
vault:UpdateOverlay()
check(not (Note() and Note().shown), "no rewards waiting: no line under the box")
vault.awayWithRewards = true
vault:UpdateOverlay()
check(Note() and Note().shown, "rewards waiting away from the vault: the line shows")
check(Note() and Note().text.text and Note().text.text:find("rolled for |cffffffffVengeance|r", 1, true),
  "it names the loot spec: " .. tostring(Note() and Note().text.text))
check(Note() and Note().level > vault.Blackout.level, "the line is above the dimming")
local specButton = vault.bgvSpecButton
check(specButton and specButton.shown and specButton.level > vault.Blackout.level, "the loot spec button is above the dimming: " .. tostring(specButton and specButton.level))
lootSpec = 577
UI.RefreshOpenFrame()
check(Note().text.text:find("Havoc", 1, true), "a loot spec change updates the line: " .. tostring(Note().text.text))
lootSpec = 0
UI.RefreshOpenFrame()
check(Note().text.text:find("Vengeance", 1, true), "back to the current spec")
vault.awayWithRewards = false
vault:UpdateOverlay()
check(not Note().shown, "the box gone: the line too")
vault.awayWithRewards = true
vault:UpdateOverlay()
check(Note().shown, "and back with the box")
-- a change while the vault is closed (here the loot spec): it's laid out afresh when it shows again
vault.shown = false
lootSpec = 577
UI.RefreshOpenFrame()
check(vault.bgvShellReady == nil, "a change while the vault is closed: laid out afresh when it shows")
vault.shown = true
vault:OnShow()
local specLabel = specButton:GetFontString().text
check(vault.bgvShellReady == true and specLabel and specLabel:find("Havoc", 1, true),
  "shown again: the loot spec button names the new spec: " .. tostring(specLabel))
lootSpec = 0
UI.RefreshOpenFrame()

-- Claim week: the vault is back to Blizzard's (and the skin's), bars and all
local done, open = Slot(), Slot()
done.CompletedIcon, open.CompletedIcon = done:CreateTexture(), open:CreateTexture()
done.CompletedActivityAnim = Widget("AnimationGroup", done)
done.CompletedActivityAnim.Stop = function(self) self.stopped = (self.stopped or 0) + 1 end
local function PlayDone() done.CompletedActivityAnim.scripts.OnPlay(done.CompletedActivityAnim) end
vault.Activities = { fresh, done, open }
UI.Apply(done, { unlocked = true, source = {} })
UI.Apply(open, { unlocked = false, source = {} })
done.CompletedIcon:Show()
check(not Seen(done.CompletedIcon), "progress week: Blizzard's checkmark stays down on the addon's slot")
local stops = done.CompletedActivityAnim.stopped or 0
PlayDone()
check((done.CompletedActivityAnim.stopped or 0) == stops + 1, "progress week: Blizzard's checkmark animation is stopped")
BGV.Rewards.ShowingWeeklyProgress = function() return false end
-- Blizzard's claim refresh: a checkmark on the finished slot, none on the locked one
done.RewardGenerated = CreateFrame("Frame", nil, done)
done.RewardGenerated.shown = false
vault.slotRefresh = { function() done.CompletedIcon:Show() end, PlayDone, function() open.CompletedIcon:Hide() end,
  function() done.RewardGenerated:Show() end }
RunTimers()
vault:OnShow()
check(vault.bgvSkinQueued == true, "claim week: the skin's late card is synced too")
check(done.RewardGenerated.shown, "claim week: Blizzard's sheen as rewards appear isn't cut")
check((done.CompletedActivityAnim.stopped or 0) == stops + 1, "claim week: Blizzard's checkmark animation plays")
check(Seen(lateBar) and Seen(lateCard), "with the vault back to Blizzard's, the skin's card and bar show again")
check(Seen(done.CompletedIcon), "claim week: the finished slot shows Blizzard's checkmark")
check(not open.CompletedIcon.shown, "claim week: the locked slot gets no checkmark from the addon")
check(done.bgvSlot == nil and open.bgvSlot == nil, "claim week: the addon lets go of the slots")
done.CompletedIcon:Show()
check(Seen(done.CompletedIcon), "claim week: Blizzard's later refreshes aren't held down")
vault.slotRefresh = nil
check(not Note().shown and not specButton.shown, "rewards already rolled: no line and no loot spec button")
vault:UpdateOverlay()
check(not Note().shown, "a later refresh doesn't bring the line back once the rewards are rolled")

-- Timers for the claim week, a bounded number of rounds: a retry that never ends fails, not hangs.
local function RunSomeTimers(rounds)
  for _ = 1, rounds or 30 do
    if #timers == 0 then return true end
    local batch = timers
    timers = {}
    for _, fn in ipairs(batch) do fn() end
  end
  return #timers == 0
end
-- The claim week at the vault: every slot holding a reward opens onto it, all together once
-- Blizzard has picked each slot's item; hovering shows the reward's tooltip; the case stays open
do
  local clock = 500
  function GetTime() return clock end
  BetterGreatVaultDB.vaultStyle = "classic"
  C_WeeklyRewards = { CanClaimRewards = function() return true end }
  vault.bgvClaimSince = nil
  C_Item = { GetItemIconByID = function(id) return 5000 + id end }
  local function RewardSlot(itemID, dbid)
    local s = Slot()
    s.ItemFrame = CreateFrame("Button", nil, s)
    s.hasRewards = true
    s.info = { rewards = { { type = 1, id = itemID + 1, itemDBID = dbid .. "x" }, { type = 1, id = itemID, itemDBID = dbid } } }
    s.GetDisplayedItemDBID = function(self) return self.displayed end
    s.CompletedIcon = s:CreateTexture()
    -- Blizzard's selection art and how it sets it (1 hidden, 2 unselected, 3 selected)
    s.SelectedTexture, s.SelectionGlow, s.UnselectedFrame = s:CreateTexture(), CreateFrame("Frame", nil, s), CreateFrame("Frame", nil, s)
    s.SetSelectionState = function(self, state)
      self.SelectedTexture:SetShown(state == 3)
      self.SelectionGlow:SetShown(state == 3)
      self.UnselectedFrame:SetShown(state == 2)
    end
    return s
  end
  local r1, r2 = RewardSlot(9001, "dbA"), RewardSlot(9002, "dbB")
  local plain = Slot()
  plain.ItemFrame = CreateFrame("Button", nil, plain)
  vault.Activities = { r1, r2, plain }
  vault.slotRefresh, vault.selectedActivity, vault.awayWithRewards = nil, nil, false
  vault.shown = true
  r1.displayed = "dbA" -- r2's item still loading
  vault:Refresh()
  check(r1.bgvFX and r1.bgvFX.shown and r1.bgvFX.phase == "closed" and not r1.bgvClaim, "an item still loading: the rewards wait, shut")
  check(r2.bgvFX and r2.bgvFX.shown and r2.bgvFX.phase == "closed", "the loading one is shut too")
  check(#timers > 0, "and it looks again shortly")
  r2.displayed = "dbB"
  RunSomeTimers()
  check(r1.bgvClaim and r1.bgvClaim.itemDBID == "dbA" and r1.bgvClaim.icon == 5000 + 9001, "loaded: the slot holds Blizzard's pick, not its other item")
  check(r1.bgvFX.phase == "opening" and r2.bgvFX.phase == "opening", "they open together")
  check(r1.ItemFrame.alpha == 0 and r2.ItemFrame.alpha == 0, "Blizzard's reward button (and any skin on it) is invisible under the case")
  check(plain.ItemFrame.alpha == nil or plain.ItemFrame.alpha == 1, "a slot without a reward keeps its button")
  check(r1.bgvFX.icons and #r1.bgvFX.icons >= 8, "the reel spins through the vault's rewards")
  check(not plain.bgvClaim and not (plain.bgvFX and plain.bgvFX.shown), "a slot without a reward stays Blizzard's")
  GameTooltip.SetWeeklyReward = function(self, id) self.weekly = id end
  r1.bgvHit.scripts.OnEnter(r1.bgvHit)
  check(GameTooltip.weekly == "dbA", "hovering a reward: its own tooltip")
  check(r1.bgvHit.scripts.OnUpdate ~= nil, "compared with your gear while hovered")
  r1.bgvHit.scripts.OnLeave(r1.bgvHit)
  RunSomeTimers()
  check(r1.bgvHit.scripts.OnUpdate == nil and r1.bgvFX.want, "left: the case stays open")
  -- shift-click: a revealed reward links once (Blizzard's button links it itself when it's under the
  -- pointer); a slot of the week's progress links nothing
  do
    local links = {}
    local modified = IsModifiedClick
    IsModifiedClick = function() return true end
    function HandleModifiedItemClick(link) links[#links + 1] = link end
    C_WeeklyRewards.GetItemHyperlink = function(id) return "link:" .. tostring(id) end
    r1.bgvHit.scripts.OnClick(r1.bgvHit, "LeftButton")
    check(#links == 1 and links[1] == "link:dbA", "shift-click on a revealed reward: its link, once")
    r1.ItemFrame.IsMouseOver = function() return true end
    r1.bgvHit.scripts.OnClick(r1.bgvHit, "LeftButton")
    check(#links == 1, "on Blizzard's own reward button: left to Blizzard's (no second link)")
    r1.ItemFrame.IsMouseOver = nil
    complete.bgvHit.scripts.OnClick(complete.bgvHit, "LeftButton")
    check(#links == 1, "a slot of the week's progress: no link")
    IsModifiedClick = modified
  end
  -- a reward selected: the others stay as they are (nothing darkens them)
  vault.selectedActivity = r1
  vault:Refresh()
  check(r2.bgvFX.claimShade == nil and r2.bgvFX.alpha ~= 0.5 and r2.bgvFX.top.alpha ~= 0.5, "a reward selected: the others stay as they are")
  check(r1.bgvFX.phase == "opening" and r1.bgvClaim.itemDBID == "dbA", "a refresh doesn't start them again")
  vault.selectedActivity = nil
  -- Blizzard's selection art (the selected reward's frame and glow, the others' unselected frame)
  -- doesn't frame the reward cases
  r1:SetSelectionState(3)
  r2:SetSelectionState(2)
  check(not r1.SelectedTexture.shown and not r2.UnselectedFrame.shown,
    "a reward selected: Blizzard's selection frames stay off the reward cases")
  check(r1.SelectionGlow.shown and not r2.SelectionGlow.shown, "the selected reward keeps Blizzard's golden glow behind its slot")
  check(not r1.Background.shown and not r2.Background.shown, "and Blizzard's card is down under them")
  -- Blizzard's own art and text on a reward's slot stay down, as on the progress week's slots
  check(not r1.Threshold.shown and not r1.Progress.shown, "a reward's slot: Blizzard's captions are down")
  r1.CompletedIcon:Show()
  r1.CompletedIcon:SetAlpha(1) -- as its fade animation does
  check(not Seen(r1.CompletedIcon), "a reward's slot: Blizzard's checkmark stays down when Blizzard shows it")
  -- the vault closing: back to Blizzard's
  vault.scripts.OnHide(vault)
  check(not r1.bgvClaim and not BGV.Case.HasClaim(r1) and not r1.bgvFX.shown, "the vault closed: back to Blizzard's")
  check(r1.ItemFrame.alpha == 1 and r2.ItemFrame.alpha == 1, "the vault closed: Blizzard's reward buttons are back")
  check(r1.Background.shown, "the vault closed: Blizzard's card is back")
  r2:SetSelectionState(2)
  check(r2.UnselectedFrame.shown, "the vault closed: Blizzard's selection art is Blizzard's again")
  check(r1.Threshold.shown and r1.Progress.shown, "the vault closed: Blizzard's captions are back")
  r1.CompletedIcon:Show()
  check(Seen(r1.CompletedIcon), "the vault closed: Blizzard's checkmark is Blizzard's again")
  -- slot animations off: the claim week is Blizzard's
  BetterGreatVaultDB.disableAnimations = true
  vault:Refresh()
  check(not r1.bgvClaim and not r1.bgvFX.shown, "slot animations off: the claim week is Blizzard's")
  BetterGreatVaultDB.disableAnimations = nil
  -- a reel's list still loading: the vault's other rewards meanwhile, the full list once it's in
  local loads, budgets = 0, {}
  local cpu = 0
  function debugprofilestop() cpu = cpu + 0.5 return cpu end
  BGV.Rewards.NewReadBudget = function(limit) return { limit = limit, reads = 0 } end
  BGV.Rewards.ClaimIcons = function(info, itemID, budget)
    loads = loads + 1
    budgets[#budgets + 1] = budget
    local list = {}
    for i = 1, (loads == 1 and 3 or 20) do list[i] = { itemID = 7000 + i, icon = 77000 + i } end
    return list, loads == 1
  end
  vault.scripts.OnHide(vault)
  r1.displayed, r2.displayed = "dbA", "dbB"
  vault.bgvClaimSince = nil
  vault:Refresh()
  local early = r1.bgvFX.icons
  local fromVault = false
  for _, entry in ipairs(early) do
    if entry.itemID == 9002 then fromVault = true end
  end
  check(fromVault, "a list still loading: the vault's other rewards fill the reel meanwhile")
  RunSomeTimers()
  local seen = {}
  for _, entry in ipairs(r1.bgvFX.icons) do seen[entry.itemID] = true end
  local count = 0
  for _ in pairs(seen) do count = count + 1 end
  check(count >= 20, "the full list swaps in while the reel spins: " .. count .. " items")
  -- one journal reading budget per pass: the reveal's reels share one, each later pass gets its own
  check(budgets[1] ~= nil and budgets[2] == budgets[1], "the reveal's reels share one reading budget")
  check(budgets[3] ~= nil and budgets[3] ~= budgets[1], "a pass that fills the reels after it has a budget of its own")
  local reveal = BGV.UI.lastReveal
  check(reveal and reveal.open > 0 and reveal.passes >= 1 and reveal.passPeak > 0,
    "what the reveal cost is kept for /bgv perf: " .. (reveal and (reveal.open .. " ms, " .. reveal.passes .. " passes") or "nothing"))
  BGV.Rewards.ClaimIcons = nil
  BGV.Rewards.NewReadBudget = nil
  vault.scripts.OnHide(vault)
  vault.bgvClaimSince = nil
  -- an item that never loads: after a while the others open without it
  r1.displayed, r2.displayed = "dbA", nil
  vault:Refresh()
  check(r1.bgvFX.phase == "closed" and r1.bgvFX.shown, "waiting on a slow item")
  clock = clock + 3
  check(RunSomeTimers(), "a slow item: the retries end")
  check(r1.bgvClaim and r1.bgvFX.phase == "opening" and not r2.bgvClaim, "an item that never loads: the others open without it")
  vault.scripts.OnHide(vault)
end

-- Blizzard's own fields on a slot stay Blizzard's (its refresh reads them): its effects go with the
-- model scene the addon hides
do
  local s = Slot()
  local effect = { cancelled = false, CancelEffect = function(self) self.cancelled = true end }
  s.activeEffect, s.activeEffectInfo = effect, { effectID = 7 }
  UI.Apply(s, { unlocked = true, source = {} })
  check(s.activeEffect == effect and s.activeEffectInfo and s.activeEffectInfo.effectID == 7 and not effect.cancelled,
    "Blizzard's effect fields on a slot stay Blizzard's")
end

-- Away from the vault once the rewards are rolled: Blizzard's read-only vault, dimmed under its
-- "unclaimed rewards" box. The slots holding rewards show them as the reveal leaves them, at once
-- and still: open, the reel stopped on the reward, its name and item level under it, nothing left
-- running, and out of the pointer's reach under the dimming. At the vault they're there to choose.
do
  local clock = 900
  function GetTime() return clock end
  BetterGreatVaultDB.vaultStyle = "classic"
  local names = { [9001] = "Apex Brute's Claw Ring", [9002] = "Miststalker's Striders" }
  local nameLoaded = true
  C_WeeklyRewards = {
    CanClaimRewards = function() return false end,
    HasGeneratedRewards = function() return true end,
    GetItemHyperlink = function(dbid) return "|Hitem:" .. (dbid == "dbA" and 9001 or 9002) .. "::|h[x]|h" end,
  }
  C_Item = {
    GetItemIconByID = function(id) return 5000 + id end,
    GetItemInfo = function(link)
      if not nameLoaded then return nil end
      return names[tonumber(tostring(link):match("item:(%d+)") or "")], nil, 4
    end,
    GetDetailedItemLevelInfo = function() return 292 end,
    GetItemQualityColor = function() return 0.64, 0.21, 0.93 end,
  }
  local function RewardSlot(itemID, dbid)
    local s = Slot()
    s.level = 200 -- Blizzard's slots sit at 200, its dimming at 1000
    s.ItemFrame = CreateFrame("Button", nil, s)
    s.ItemFrame.level = 250
    s.hasRewards = true
    s.info = { rewards = { { type = 1, id = itemID, itemDBID = dbid } } }
    s.GetDisplayedItemDBID = function() return dbid end
    s.CompletedIcon = s:CreateTexture()
    return s
  end
  local function Drive(seconds)
    for _ = 1, math.floor(seconds * 60 + 0.5) do
      clock = clock + 1 / 60
      local driver = CaseDriver()
      if driver then driver.scripts.OnUpdate(driver, 1 / 60) end
    end
  end
  local a, b, plain = RewardSlot(9001, "dbA"), RewardSlot(9002, "dbB"), Slot()
  vault.Activities = { a, b, plain }
  vault.selectedActivity, vault.slotRefresh = nil, nil
  vault.awayWithRewards = true
  vault.bgvClaimSince = nil
  vault.shown = true
  vault:Refresh()
  for _, s in ipairs({ a, b }) do
    local f = s.bgvFX
    local label = f and f.claimLabel
    check(s.bgvClaim and f and f.shown and f.phase == "open" and f.settled, "away: the reward's case is open and still")
    check(f and f.landedAt and f.landItem and f.marker.alpha == 0, "away: the reel stopped on the reward")
    check(label and label.shown and label.name.text == names[s.bgvClaim.itemID] and label.ilvl.text == "292 ilvl",
      "away: its name and item level under it: " .. tostring(label and label.name.text))
    check(not (s.bgvHit and s.bgvHit.shown), "away: nothing of the addon's to point at")
    check(s.ItemFrame.alpha == 0 and not s.Threshold.shown and not s.Progress.shown, "away: Blizzard's button and captions are down under the case")
    check(not s.Background.shown, "away: Blizzard's card is down under the case")
    check(f and f.level < vault.Blackout.level and f.top.level < vault.Blackout.level and label and label.level < vault.Blackout.level,
      "away: all under Blizzard's dimming")
  end
  check(not CaseDriver(), "away: nothing left running")
  check(not plain.bgvClaim and not (plain.bgvFX and plain.bgvFX.shown), "away: a slot without a reward stays Blizzard's")
  -- a later refresh leaves them as they are
  local landed = a.bgvFX.landedAt
  vault:Refresh()
  check(a.bgvFX.landedAt == landed and a.bgvFX.settled and not CaseDriver(), "away: a refresh leaves them as they are")
  -- at the vault, the window still open: the same rewards, now there to choose
  C_WeeklyRewards.CanClaimRewards = function() return true end
  vault.awayWithRewards = false
  vault:Refresh()
  check(a.bgvHit and a.bgvHit.shown and a.bgvFX.landedAt == landed, "at the vault: the same rewards, now there to choose")
  vault.scripts.OnHide(vault)
  check(not a.bgvClaim and not a.bgvFX.shown and a.ItemFrame.alpha == 1 and a.Threshold.shown, "the vault closed: back to Blizzard's")
  check(a.Background.shown, "the vault closed: Blizzard's card is back")
  -- a reward's name the game hasn't loaded yet: landed, it waits for it in real time, then settles
  C_WeeklyRewards.CanClaimRewards = function() return false end
  vault.awayWithRewards = true
  vault.bgvClaimSince = nil
  nameLoaded = false
  vault:Refresh()
  check(a.bgvFX.landedAt and not a.bgvFX.settled and CaseDriver() and not a.bgvFX.claimLabel.shown,
    "away, a name still loading: landed, waiting for it")
  nameLoaded = true
  Drive(0.5)
  check(a.bgvFX.claimLabel.shown and a.bgvFX.claimLabel.name.text == names[9001], "away: the name shows once loaded")
  Drive(3)
  check(a.bgvFX.settled and not CaseDriver(), "away: then all is still")
  vault.scripts.OnHide(vault)
  -- slot animations off: the vault is Blizzard's
  BetterGreatVaultDB.disableAnimations = true
  vault:Refresh()
  check(not a.bgvClaim and not (a.bgvFX and a.bgvFX.shown) and a.ItemFrame.alpha == 1, "away, slot animations off: Blizzard's")
  BetterGreatVaultDB.disableAnimations = nil
  vault.scripts.OnHide(vault)
end

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  check(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end

print(fails == 0 and "vault ui checks passed" or (fails .. " vault ui checks failed"))
