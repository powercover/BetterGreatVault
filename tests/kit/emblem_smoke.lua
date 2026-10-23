-- The spinning emblem (Utils.CreateEmblem) run through whole cycles at 60 and 20 frames a second.
if not unpack then unpack = table.unpack end
local fails = 0
local function check(ok, message) if not ok then fails = fails + 1; print("EMBLEM FAIL: " .. message) end end

local function Region(kind)
  local r = { kind = kind, shown = true, alpha = 1, rotation = 0, scripts = {}, children = {}, scale = 1, x = 0, y = 0 }
  function r:SetSize(w, h) self.w, self.h = w, h end
  function r:SetPoint(_, _, _, x, y) self.x, self.y = x or 0, y or 0 end
  function r:SetTexture(file) self.file = file end
  function r:SetRotation(radians) self.rotation = radians end
  function r:SetTexCoord(l, rr, t, b) self.coords = { l, rr, t, b } end
  function r:SetAlpha(a) self.alpha = a end
  function r:Show() self.shown = true end
  function r:Hide() self.shown = false end
  function r:SetShown(v) self.shown = v and true or false end
  function r:SetScale(s) self.scale = s end
  function r:SetScript(name, fn) self.scripts[name] = fn end
  function r:CreateTexture(_, layer, _, sublevel)
    local t = Region("Texture")
    t.layer, t.sublevel = layer, sublevel
    table.insert(self.children, t)
    return t
  end
  return r
end
function CreateFrame(kind, _, parent)
  local f = Region(kind)
  if parent then table.insert(parent.children, f) end
  return f
end
function GetLocale() return "enUS" end
BetterGreatVaultDB = {}
GameFontHighlightSmall, GameFontHighlight, GameFontNormal = {}, {}, {}

local BGV = {}
for _, path in ipairs({ "Locales/Locales.lua", "Utils.lua" }) do assert(loadfile(path))("BetterGreatVault", BGV) end

local parent = Region("Frame")
local emblem = BGV.Utils.CreateEmblem(parent, 48)
local body = emblem.children[1]
local files = {}
for _, t in ipairs(body.children) do files[#files + 1] = (t.file or ""):match("([^\\]+)$") end
check(table.concat(files, ","):find("MinimapBase,EmblemBlur,MinimapWheel,EmblemTrails,MinimapGem,EmblemArcs,CasePuffs", 1, true),
  "the icon's layers and the effects, in drawing order: " .. table.concat(files, ","))
local function Texture(name)
  for _, t in ipairs(body.children) do if (t.file or ""):find(name .. "$") then return t end end
end
local wheel, blur, trails, arcs = Texture("MinimapWheel"), Texture("EmblemBlur"), Texture("EmblemTrails"), Texture("EmblemArcs")
check(arcs.w == 48 * 1.6, "the arcs reach past the rim")
check(not blur.shown and not trails.shown and not arcs.shown and wheel.alpha == 1, "at rest: just the icon")

local spin = emblem.spin
local function Run(seconds, fps, observe)
  local frames = math.floor(seconds * fps + 0.5)
  for _ = 1, frames do
    local before = spin.angle
    emblem.scripts.OnUpdate(emblem, 1 / fps)
    if observe then observe(before) end
  end
end

-- one whole cycle at 60 frames a second, from a showing
emblem.scripts.OnShow(emblem)
check(spin.t == 1.4 and spin.scale == 1, "a showing starts the cycle over")
local seen = { maxSpeed = 0, minScale = 1, maxScale = 1, backwards = false, maxPuffs = 0, rattled = false, fastEffects = false,
  restAfterBurst = false, burstAt = nil, bigStep = 0, shapeSet = {}, mirrored = false, lowTilt = 9, highTilt = -9 }
local clock = 0
Run(6.2, 60, function(before)
  clock = clock + 1 / 60
  local step = (spin.angle - before + math.pi) % (2 * math.pi) - math.pi
  seen.bigStep = math.max(seen.bigStep, math.abs(step))
  if step < -0.001 then seen.backwards = true end
  seen.maxSpeed = math.max(seen.maxSpeed, spin.speed)
  seen.minScale = math.min(seen.minScale, spin.scale)
  seen.maxScale = math.max(seen.maxScale, spin.scale)
  local active = 0
  for _, puff in ipairs(spin.puffs) do if puff.active then active = active + 1 end end
  seen.maxPuffs = math.max(seen.maxPuffs, active)
  if active >= 4 and not seen.burstAt then seen.burstAt = clock end
  for _, puff in ipairs(spin.puffs) do
    if puff.active and puff.texture.coords then
      local l, r = puff.texture.coords[1], puff.texture.coords[2]
      seen.shapeSet[math.floor(math.min(l, r) * 4 + 0.5)] = true
      if l > r then seen.mirrored = true end
      seen.lowTilt = math.min(seen.lowTilt, puff.texture.rotation)
      seen.highTilt = math.max(seen.highTilt, puff.texture.rotation)
    end
  end
  if body.x ~= 0 or body.y ~= 0 then seen.rattled = true end
  if spin.effect == 1 and blur.shown and trails.shown and arcs.shown and arcs.alpha == 1 and wheel.alpha < 0.5 then
    seen.fastEffects = true
  end
  if seen.fastEffects and spin.speed < 2 and spin.effect == 0 and not blur.shown and body.x == 0 then
    seen.restAfterBurst = true
  end
end)
seen.shapes = 0
for _ in pairs(seen.shapeSet) do seen.shapes = seen.shapes + 1 end
seen.tilts = seen.highTilt - seen.lowTilt
check(seen.maxSpeed == 28, "it gets to full speed: " .. seen.maxSpeed)
check(seen.backwards, "the wind-up backs off before the burst")
check(seen.burstAt and seen.burstAt > 1.0 and seen.burstAt < 1.6, "a burst of puffs about a second after showing: " .. tostring(seen.burstAt))
check(seen.maxPuffs <= 6, "never more than six puffs: " .. seen.maxPuffs)
check(seen.shapes >= 3 and seen.mirrored and seen.tilts > 0.3, "puffs vary in shape, mirroring and tilt: "
  .. seen.shapes .. " shapes, tilt spread " .. seen.tilts)
check(seen.fastEffects, "flat out: blur, streaks and arcs up, the handle faded behind them")
check(seen.rattled, "it rattles at speed")
check(seen.restAfterBurst, "it eases back to a slow, plain spin")
check(seen.minScale < 0.95 and seen.maxScale > 1.03 and seen.maxScale < 1.15, "squash and stretch: " .. seen.minScale .. " .. " .. seen.maxScale)
check(seen.bigStep < 0.5, "at 60 fps the handle turns under 0.5 rad a frame: " .. seen.bigStep)
local active = 0
for _, puff in ipairs(spin.puffs) do if puff.active or puff.texture.shown then active = active + 1 end end
check(active == 0, "all puffs gone by the slow spin")

-- at 20 frames a second the handle's step is capped, so it never looks like turning backwards
local worst = 0
Run(6.2, 20, function(before)
  local step = (spin.angle - before + math.pi) % (2 * math.pi) - math.pi
  worst = math.max(worst, math.abs(step))
end)
check(worst <= 0.65 + 1e-9, "per-frame turn capped at low frame rates: " .. worst)

-- a hitch doesn't jump the cycle
local t = spin.t
emblem.scripts.OnUpdate(emblem, 3)
check(math.abs(((spin.t - t) % 6.2) - 0.05) < 1e-9, "a long frame counts as a short one")

-- showing again mid-burst: back to the start, no puffs left over
Run(1.6, 60)
emblem.scripts.OnShow(emblem)
local left = 0
for _, puff in ipairs(spin.puffs) do if puff.active or puff.texture.shown then left = left + 1 end end
check(spin.t == 1.4 and left == 0 and not arcs.shown, "a new showing starts clean")

-- nothing else went wrong out of sight: an error the addon caught and noted (Utils.NoteError) fails
for _, noted in ipairs(BGV.errors or {}) do
  check(false, "an error was caught and noted: " .. tostring(noted.label) .. ": " .. tostring(noted.message))
end

print(fails == 0 and "emblem checks passed" or (fails .. " emblem checks failed"))
