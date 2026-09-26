local _, BGV = ...

BGV.LootTable = {}

local FILTERS = {
    { id = "ALL", label = "All gear" },
    { id = "Head", label = "Head" },
    { id = "Neck", label = "Neck" },
    { id = "Shoulder", label = "Shoulder" },
    { id = "Cloak", label = "Cloak" },
    { id = "Chest", label = "Chest" },
    { id = "Wrist", label = "Wrist" },
    { id = "Hands", label = "Hands" },
    { id = "Waist", label = "Waist" },
    { id = "Legs", label = "Legs" },
    { id = "Feet", label = "Feet" },
    { id = "Finger", label = "Finger" },
    { id = "Trinket", label = "Trinket" },
    { id = "Weapon", label = "Weapon" },
}

-- The four secondary stats, in menu order. `global` is the game's localized name, which is also
-- how the tooltip writes the stat; `short` labels the filter button.
local SECONDARY_STATS = {
    { id = "CRIT", global = "ITEM_MOD_CRIT_RATING_SHORT", name = "Critical Strike", short = "Crit" },
    { id = "HASTE", global = "ITEM_MOD_HASTE_RATING_SHORT", name = "Haste", short = "Haste" },
    { id = "MASTERY", global = "ITEM_MOD_MASTERY_RATING_SHORT", name = "Mastery", short = "Mastery" },
    { id = "VERSATILITY", global = "ITEM_MOD_VERSATILITY", name = "Versatility", short = "Vers" },
}

local CATEGORIES = {
    { id = "raid", title = "Raid", match = "Raid" },
    { id = "mplus", title = "Mythic+", match = "Activities" },
    { id = "world", title = "World", match = "World" },
}

local LEFT_W = 188
local LIST_TOP = 132
local ROW_H = 30
local NAME_X = 40
local LEVEL_W = 80
local STATS_W = 150
local SLOT_W = 120
local GROUP_H = 26
local STAT_LINE_H = 12

-- Column x offsets within a row of the given width; the header uses the same geometry.
local function Columns(width)
    local slotX = width - SLOT_W - 8
    local statsX = slotX - STATS_W
    local levelX = statsX - LEVEL_W
    return levelX, statsX, slotX
end

local frame
local rail
local columnHeader
local scroll
local child
local headerTitle
local headerReward
local filterLabel
local statLabel
local specButton
local filterID = "ALL"
-- Selected secondary stats (id -> true). None: no filter; one: items with it; two: items with
-- both; three or more: items with at least one of them.
local statFilter = {}
-- Secondary stats per itemID:itemLevel (see EntryStats).
local statCache = {}
local selectedKey
local solo
local pool = {}
local linkPool = {}
local linkRows = {}
local itemCache = {}
local templateCache = {}
local Layout
local pendingWatch
local chunkQueued

local Pixel = BGV.Utils.Pixel

local function CategoryFor(slot)
    if type(slot) ~= "table" then
        return nil
    end
    for _, category in ipairs(CATEGORIES) do
        if BGV.Utils.SameType(slot.type, BGV.Utils.ThresholdType(category.match)) then
            return category
        end
    end
end

local function SlotKey(category, slot)
    return category.id .. ":" .. tostring(slot.index)
end

local function SlotTitle(slot)
    local title = "Slot " .. tostring(slot.index or "?")
    if BGV.Utils.IsUsableNumber(slot.threshold) and type(slot.unit) == "string" then
        title = string.format("%s · %d %s", title, slot.threshold, slot.unit)
    end
    if type(slot.qualifier) == "string" and slot.qualifier ~= "" then
        title = title .. " · " .. slot.qualifier
    end
    if not slot.unlocked then
        title = title .. " · Locked"
    end
    return title
end

local function RewardLine(slot)
    if type(slot) ~= "table" then
        return ""
    end
    if type(slot.upgradeTrack) == "string"
        and BGV.Utils.IsUsableNumber(slot.upgradeLevel)
        and BGV.Utils.IsUsableNumber(slot.upgradeMax)
        and BGV.Utils.IsUsableNumber(slot.itemLevel) then
        return string.format("%s %d/%d (%d ilvl)", slot.upgradeTrack, slot.upgradeLevel, slot.upgradeMax, slot.itemLevel)
    end
    if BGV.Utils.IsUsableNumber(slot.itemLevel) then
        return string.format("%d ilvl", slot.itemLevel)
    end
    return ""
end

local function StatName(stat)
    local text = _G[stat.global]
    if type(text) == "string" and text ~= "" then
        return text
    end
    return stat.name
end

-- The amount if tooltip line `text` is exactly this stat ("+123 Haste"); nil for anything else,
-- such as an "Equip:" line that mentions the stat.
local function StatAmount(text, name)
    local start, finish = text:find(name, 1, true)
    if not start then
        return nil
    end
    local rest = text:sub(1, start - 1) .. text:sub(finish + 1)
    local number = rest:match("^%s*%+%s*(%d[%d%.,%s\194\160]*)%s*$")
    local amount = number and tonumber((number:gsub("%D", "")))
    if amount and amount > 0 then
        return amount
    end
end

local NO_STATS = {}

-- The item's secondary stats at the level the vault awards, read from the same tooltip the row
-- shows (C_TooltipInfo.GetItemKey, the data behind GameTooltip:SetItemKey), highest amount
-- first. Returns nil while the item's tooltip data hasn't loaded.
local function EntryStats(entry)
    local info = C_TooltipInfo
    if not (info and type(info.GetItemKey) == "function") or not BGV.Utils.IsUsableNumber(entry.itemID) then
        return NO_STATS
    end
    local key = tostring(entry.itemID) .. ":" .. tostring(entry.itemLevel)
    if statCache[key] then
        return statCache[key]
    end
    local data
    if BGV.Utils.IsUsableNumber(entry.itemLevel) then
        data = BGV.Utils.Call(info.GetItemKey, entry.itemID, entry.itemLevel, 0)
    elseif type(info.GetItemByID) == "function" then
        data = BGV.Utils.Call(info.GetItemByID, entry.itemID)
    end
    local lines = type(data) == "table" and data.lines
    if type(lines) ~= "table" or #lines < 3 then
        return nil
    end
    local stats = {}
    for _, line in ipairs(lines) do
        local text = type(line) == "table" and line.leftText
        if not BGV.Utils.IsSecret(text) and type(text) == "string" and text ~= "" then
            text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
            for _, stat in ipairs(SECONDARY_STATS) do
                local name = StatName(stat)
                local amount = StatAmount(text, name)
                if amount then
                    stats[#stats + 1] = { id = stat.id, name = name, amount = amount }
                    break
                end
            end
        end
    end
    table.sort(stats, function(left, right)
        if left.amount ~= right.amount then
            return left.amount > right.amount
        end
        return left.name < right.name
    end)
    statCache[key] = stats
    return stats
end

local function SelectedStats()
    local selected = {}
    for _, stat in ipairs(SECONDARY_STATS) do
        if statFilter[stat.id] then
            selected[#selected + 1] = stat
        end
    end
    return selected
end

local function PassesStatFilter(stats, selected)
    if #selected == 0 then
        return true
    end
    local has = {}
    for _, stat in ipairs(stats) do
        has[stat.id] = true
    end
    if #selected <= 2 then
        for _, stat in ipairs(selected) do
            if not has[stat.id] then
                return false
            end
        end
        return true
    end
    for _, stat in ipairs(selected) do
        if has[stat.id] then
            return true
        end
    end
    return false
end

local function StatFilterKey()
    local ids = {}
    for _, stat in ipairs(SelectedStats()) do
        ids[#ids + 1] = stat.id
    end
    return table.concat(ids, "+")
end

local function StatFilterLabel()
    local selected = SelectedStats()
    if #selected == 0 then
        return "All stats"
    elseif #selected == 1 then
        return StatName(selected[1])
    elseif #selected == #SECONDARY_STATS then
        return "Any secondary"
    end
    local names = {}
    for _, stat in ipairs(selected) do
        names[#names + 1] = stat.short
    end
    return table.concat(names, #selected == 2 and " + " or " / ")
end

local function CacheKey(slot)
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or ""
    local spec = BGV.Utils.LootSpecID()
    return table.concat({
        tostring(guid),
        tostring(spec),
        tostring(slot.type),
        tostring(slot.index),
        tostring(slot.itemLevel),
        tostring(slot.level),
        tostring(filterID),
        StatFilterKey(),
    }, ":")
end

local function SlotItems(slot)
    local key = CacheKey(slot)
    local cached = itemCache[key]
    if cached then
        return cached, false
    end
    local list = {}
    local pending = false
    local selected = SelectedStats()
    if slot.unlocked and BGV.Rewards and type(BGV.Rewards.ItemsForSlot) == "function" then
        local found, stillLoading = BGV.Rewards.ItemsForSlot(slot)
        pending = stillLoading == true
        if type(found) == "table" then
            for _, entry in ipairs(found) do
                if filterID == "ALL" or entry.equipLabel == filterID then
                    -- Stats still loading: list the item (without stats) unless filtering by
                    -- stat, and keep the list pending so it's redrawn once they arrive.
                    local stats = EntryStats(entry)
                    if not stats then
                        pending = true
                        if #selected == 0 then
                            list[#list + 1] = entry
                        end
                    elseif PassesStatFilter(stats, selected) then
                        list[#list + 1] = entry
                    end
                end
            end
        end
    end
    if pending then
        return list, true
    end
    itemCache[key] = list
    return list, false
end

function BGV.LootTable.ItemsFor(slot)
    return SlotItems(slot)
end

-- While a list is still loading we retry on our own, not only on journal events: item data
-- (after a spec change, for example) arrives through other events, and a pass can come back
-- still loading without anything new to trigger the next one.
local POLL_DELAY = 0.25
local MAX_STALLS = 40
local stalls = 0

local function ResetWatch()
    pendingWatch = nil
    stalls = 0
end

function BGV.LootTable.Invalidate()
    itemCache = {}
    templateCache = {}
    ResetWatch()
    if BGV.Rewards and type(BGV.Rewards.InvalidateIcons) == "function" then
        BGV.Rewards.InvalidateIcons()
    end
    if frame and type(frame.IsShown) == "function" and frame:IsShown() then
        Layout()
    end
end

-- Rebuilds the shown lists from Rewards' caches, keeping them (unlike Invalidate): used when
-- Rewards dropped just the batches that can now complete (Rewards.RetryGivenUp).
function BGV.LootTable.Reload()
    itemCache = {}
    templateCache = {}
    ResetWatch()
    if frame and type(frame.IsShown) == "function" and frame:IsShown() then
        Layout()
    end
end

function BGV.LootTable.RefreshPending(delay)
    if chunkQueued or not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        return
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    chunkQueued = true
    C_Timer.After(delay or 0, function()
        chunkQueued = false
        if frame and frame:IsShown() then
            Layout()
        end
    end)
end

function BGV.LootTable.Nudge()
    if not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        return
    end
    ResetWatch()
    BGV.LootTable.RefreshPending()
end

local seenCharacter

function BGV.LootTable.OnCharacterChanged()
    local guid = type(UnitGUID) == "function" and UnitGUID("player") or nil
    if guid == seenCharacter then
        return
    end
    seenCharacter = guid
    BGV.LootTable.Invalidate()
    if BGV.Rewards and type(BGV.Rewards.InvalidateIcons) == "function" then
        BGV.Rewards.InvalidateIcons()
    end
end

local function BuildModel()
    local model = {}
    local snapshot = BGV.GreatVault and BGV.GreatVault.GetSnapshot and BGV.GreatVault.GetSnapshot() or {}
    for _, category in ipairs(CATEGORIES) do
        local group = { id = category.id, title = category.title, slots = {} }
        for _, slot in ipairs(snapshot) do
            local found = CategoryFor(slot)
            if found and found.id == category.id then
                group.slots[#group.slots + 1] = {
                    id = SlotKey(category, slot),
                    title = "Slot " .. tostring(slot.index or "?"),
                    slot = slot,
                }
            end
        end
        if #group.slots > 0 then
            model[#model + 1] = group
        end
    end
    return model
end

local function FindSection(model, key)
    for _, group in ipairs(model) do
        for _, section in ipairs(group.slots) do
            if section.id == key then
                return section
            end
        end
    end
end

local function FirstSection(model, preferUnlocked)
    local fallback
    for _, group in ipairs(model) do
        for _, section in ipairs(group.slots) do
            if not fallback then
                fallback = section
            end
            if not preferUnlocked or section.slot.unlocked then
                return section
            end
        end
    end
    return fallback
end

local function SplitLink(link)
    local body = type(link) == "string" and link:match("item:([%d:]*)") or nil
    if not body or body == "" then
        return nil
    end
    local parts = {}
    for part in (body .. ":"):gmatch("([^:]*):") do
        parts[#parts + 1] = part
    end
    if #parts < 13 then
        return nil
    end
    return parts
end

local function Assemble(parts)
    return "item:" .. table.concat(parts, ":")
end

local function Measure(link)
    if not (C_Item and type(C_Item.GetDetailedItemLevelInfo) == "function") or type(link) ~= "string" then
        return nil
    end
    local level = BGV.Utils.Call(C_Item.GetDetailedItemLevelInfo, link)
    if BGV.Utils.IsUsableNumber(level) and level > 0 then
        return level
    end
end

local function WithoutBonus(parts, dropIndex)
    local count = tonumber(parts[13]) or 0
    local nextParts = {}
    for index = 1, 12 do
        nextParts[index] = parts[index]
    end
    local kept = {}
    for index = 1, count do
        if index ~= dropIndex then
            kept[#kept + 1] = parts[13 + index]
        end
    end
    nextParts[13] = tostring(#kept)
    local pos = 13
    for _, bonus in ipairs(kept) do
        pos = pos + 1
        nextParts[pos] = bonus
    end
    for index = 14 + count, #parts do
        pos = pos + 1
        nextParts[pos] = parts[index]
    end
    return nextParts
end

local function TemplateFor(rewardLink, target)
    local key = tostring(rewardLink) .. "@" .. tostring(target)
    if templateCache[key] then
        return templateCache[key]
    end
    local parts = SplitLink(rewardLink)
    local link = parts and Assemble(parts) or rewardLink
    local level = Measure(link)
    local guard = 0
    while parts and level and target and level > target and guard < 6 do
        guard = guard + 1
        local count = tonumber(parts[13]) or 0
        local matched
        local bestParts
        local bestLevel
        for index = 1, count do
            local trial = WithoutBonus(parts, index)
            local trialLevel = Measure(Assemble(trial))
            if trialLevel == target then
                parts = trial
                link = Assemble(trial)
                level = trialLevel
                matched = true
                break
            end
            if trialLevel and trialLevel < level and trialLevel > target and (not bestLevel or trialLevel < bestLevel) then
                bestLevel = trialLevel
                bestParts = trial
            end
        end
        if matched or not bestParts then
            break
        end
        parts = bestParts
        link = Assemble(parts)
        level = bestLevel
    end
    templateCache[key] = link
    return link
end

local function SwapItem(link, itemID)
    local parts = SplitLink(link)
    if parts then
        parts[1] = tostring(itemID)
        return Assemble(parts)
    end
    local rest = type(link) == "string" and (link:match("item:%d+(.-)|h") or link:match("item:%d+(.*)")) or ""
    return "item:" .. tostring(itemID) .. (rest or "")
end

local function TipLink(entry)
    if not BGV.Utils.IsUsableNumber(entry.itemID) then
        return nil
    end
    if type(entry.rewardLink) == "string" and entry.rewardLink ~= "" and BGV.Utils.IsUsableNumber(entry.itemLevel) then
        local template = TemplateFor(entry.rewardLink, entry.itemLevel)
        local link = SwapItem(template, entry.itemID)
        local level = Measure(link)
        if level and level > entry.itemLevel then
            return TemplateFor(link, entry.itemLevel)
        end
        return link
    end
    return "item:" .. tostring(entry.itemID)
end

local function EntryLink(entry)
    if not entry.tipLink then
        entry.tipLink = TipLink(entry)
    end
    return entry.tipLink
end

-- The vault preview link can't be reliably re-scaled to an arbitrary rank (e.g. its ceiling
-- bonus doesn't map to the normal cap by removing or shifting bonus IDs), so render the item
-- by ID at the exact level the slot will award, the same way the Auction House does.
local function FillTooltip(entry)
    if BGV.Utils.IsUsableNumber(entry.itemLevel) and type(GameTooltip.SetItemKey) == "function" then
        GameTooltip:SetItemKey(entry.itemID, entry.itemLevel, 0)
    else
        local link = EntryLink(entry)
        if type(link) == "string" then
            GameTooltip:SetHyperlink(link)
        else
            GameTooltip:SetItemByID(entry.itemID)
        end
    end
    if type(GameTooltip_ShowCompareItem) == "function" then
        BGV.Utils.Call(GameTooltip_ShowCompareItem, GameTooltip)
    end
end

-- SetItemKey draws the item's base quality, but the vault can award it higher (Mythic+
-- dungeon loot is blue at base and epic from the vault), so match the title to the reward.
local function PaintTitle(tooltip, entry)
    local colors = ITEM_QUALITY_COLORS and BGV.Utils.IsUsableNumber(entry.quality) and ITEM_QUALITY_COLORS[entry.quality]
    local title = colors and tooltip.GetName and _G[tooltip:GetName() .. "TextLeft1"]
    if title then
        title:SetTextColor(colors.r, colors.g, colors.b)
    end
end

if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip ~= GameTooltip then
            return
        end
        local owner = tooltip:GetOwner()
        if owner and owner.bgvLootRow and owner.entry then
            PaintTitle(tooltip, owner.entry)
        end
    end)
end

local function ShowItemTooltip(owner, entry)
    if not GameTooltip or not entry or not BGV.Utils.IsUsableNumber(entry.itemID) then
        return
    end
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    FillTooltip(entry)
    PaintTitle(GameTooltip, entry)
    if Item and type(Item.CreateFromItemID) == "function" then
        local item = BGV.Utils.Call(Item.CreateFromItemID, Item, entry.itemID)
        if item and type(item.IsItemDataCached) == "function" and not item:IsItemDataCached() and type(item.ContinueOnLoad) == "function" then
            item:ContinueOnLoad(function()
                if owner:IsShown() and owner:IsMouseOver() and owner.entry == entry then
                    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                    FillTooltip(entry)
                    PaintTitle(GameTooltip, entry)
                end
            end)
        end
    end
end

local function Acquire()
    local row = table.remove(pool)
    if not row then
        row = CreateFrame("Button", nil, child)
        row.bgvLootRow = true
        row:RegisterForClicks("AnyUp")
        row.stripe = Pixel(row, "BACKGROUND", 1, 1, 1, 0.03)
        row.stripe:SetDrawLayer("BACKGROUND", -1)
        row.stripe:SetAllPoints()
        row.stripe:Hide()
        row.band = Pixel(row, "BACKGROUND", 0.85, 0.65, 0.2, 0.12)
        row.band:SetDrawLayer("BACKGROUND", -1)
        row.band:SetAllPoints()
        row.band:Hide()
        row.bandEdge = Pixel(row, "ARTWORK", 0.85, 0.65, 0.2, 0.9)
        row.bandEdge:SetWidth(2)
        row.bandEdge:SetPoint("TOPLEFT")
        row.bandEdge:SetPoint("BOTTOMLEFT")
        row.bandEdge:Hide()
        row.iconBG = Pixel(row, "BACKGROUND", 1, 1, 1, 1)
        row.iconBG:SetSize(26, 26)
        row.iconBG:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 9, 0)
        row.iconBG:SetPoint("CENTER", row.icon, "CENTER", 0, 0)

        row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.level:SetJustifyH("LEFT")
        row.level:SetWordWrap(false)
        row.slot = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.slot:SetJustifyH("LEFT")
        row.slot:SetWordWrap(false)
        -- One font string per secondary stat, stacked (see PaintStats).
        row.statLines = {}

        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
        row:SetScript("OnEnter", function(self)
            ShowItemTooltip(self, self.entry)
        end)
        row:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnClick", function(self, button)
            if button == "LeftButton" and IsModifiedClick() and self.entry and type(HandleModifiedItemClick) == "function" then
                local link = EntryLink(self.entry)
                if link then
                    HandleModifiedItemClick(link)
                end
            end
        end)
    end
    row:SetHeight(ROW_H)
    row.stripe:Hide()
    row.band:Hide()
    row.bandEdge:Hide()
    row.iconBG:Hide()
    row.icon:SetTexture(nil)
    row.name:SetFontObject(GameFontHighlight)
    row.name:SetText("")
    row.level:SetText("")
    row.slot:SetText("")
    row.slot:SetTextColor(0.7, 0.7, 0.72)
    for _, line in ipairs(row.statLines) do
        line:SetText("")
        line:Hide()
    end
    if row:GetHighlightTexture() then
        row:GetHighlightTexture():SetAlpha(1)
    end
    row:Show()
    return row
end

local function ReleaseRows()
    if not child then
        return
    end
    -- Every row is a child of `child`, so rebuild the pool from scratch. Appending would
    -- re-add rows still sitting in the pool from the last layout, and a duplicated row gets
    -- positioned twice, leaving an empty gap where it was first placed.
    pool = {}
    for _, row in ipairs({ child:GetChildren() }) do
        row:Hide()
        row.entry = nil
        pool[#pool + 1] = row
    end
end

local function QualityColor(entry)
    local colors = ITEM_QUALITY_COLORS
    local quality = entry.quality
    if colors and BGV.Utils.IsUsableNumber(quality) and colors[quality] then
        return colors[quality].r, colors[quality].g, colors[quality].b
    end
    return 0.95, 0.95, 0.95
end

local function PaintLinks(model)
    for _, link in ipairs(linkRows) do
        link:Hide()
    end
    local shown = 0
    local function Take()
        shown = shown + 1
        local link = linkRows[shown]
        if not link then
            link = table.remove(linkPool)
        end
        if not link then
            link = CreateFrame("Button", nil, rail)
            link:SetHeight(28)
            link:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")
            local bar = Pixel(link, "ARTWORK", 0.85, 0.65, 0.2, 1)
            bar:SetSize(2, 14)
            bar:SetPoint("LEFT", link, "LEFT", 0, 0)
            bar:Hide()
            link.bar = bar
            local label = link:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", link, "LEFT", 12, 0)
            label:SetPoint("RIGHT", link, "RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            label:SetWordWrap(false)
            link.label = label
            local underline = Pixel(link, "OVERLAY", 0.96, 0.96, 0.96, 0.7)
            underline:SetHeight(1)
            underline:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -1)
            underline:SetPoint("TOPRIGHT", label, "BOTTOMRIGHT", 0, -1)
            underline:Hide()
            link.underline = underline
            link:SetScript("OnEnter", function(self)
                if self.kind == "slot" then
                    self.label:SetTextColor(0.96, 0.96, 0.96)
                    self.underline:Show()
                end
            end)
            link:SetScript("OnLeave", function(self)
                self.underline:Hide()
                if self.kind == "slot" and not self.selected then
                    self.label:SetTextColor(0.46, 0.46, 0.48)
                end
            end)
            linkRows[shown] = link
        end
        link:Show()
        return link
    end

    local y = 36
    for _, group in ipairs(model) do
        local header = Take()
        header.kind = "header"
        header.selected = false
        header:SetScript("OnClick", nil)
        if header:GetHighlightTexture() then
            header:GetHighlightTexture():SetAlpha(0)
        end
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -y)
        header:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -y)
        header.bar:Hide()
        header.underline:Hide()
        header.label:SetText(group.title)
        header.label:SetTextColor(0.85, 0.65, 0.2)
        y = y + 28
        for _, section in ipairs(group.slots) do
            local link = Take()
            local selected = section.id == selectedKey
            link.kind = "slot"
            link.selected = selected
            if link:GetHighlightTexture() then
                link:GetHighlightTexture():SetAlpha(1)
            end
            link:ClearAllPoints()
            link:SetPoint("TOPLEFT", rail, "TOPLEFT", 28, -y)
            link:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -y)
            link.bar:SetShown(selected)
            link.underline:Hide()
            link.label:SetText(section.title)
            if selected then
                link.label:SetTextColor(0.96, 0.96, 0.96)
            else
                link.label:SetTextColor(0.46, 0.46, 0.48)
            end
            local sectionID = section.id
            link:SetScript("OnClick", function()
                selectedKey = sectionID
                Layout()
            end)
            y = y + 28
        end
        y = y + 8
    end
end

local function SlotName(entry)
    local label = type(entry.equipLoc) == "string" and _G[entry.equipLoc]
    if type(label) == "string" and label ~= "" then
        return label
    end
    return entry.equipLabel or ""
end

local function PlaceColumns(row, rowWidth)
    local levelX, statsX, slotX = Columns(rowWidth)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(math.max(40, levelX - NAME_X - 10))
    row.level:ClearAllPoints()
    row.level:SetPoint("LEFT", row, "LEFT", levelX, 0)
    row.level:SetWidth(LEVEL_W - 8)
    row.statsX = statsX
    row.slot:ClearAllPoints()
    row.slot:SetPoint("LEFT", row, "LEFT", slotX, 0)
    row.slot:SetWidth(SLOT_W - 8)
end

-- Draws `texts` in the stats column, one line each, centred vertically in the row.
local function PaintStats(row, texts, r, g, b)
    local count = #texts
    for index, text in ipairs(texts) do
        local line = row.statLines[index]
        if not line then
            line = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            line:SetJustifyH("LEFT")
            line:SetWordWrap(false)
            row.statLines[index] = line
        end
        line:ClearAllPoints()
        line:SetPoint("LEFT", row, "LEFT", row.statsX or 0, ((count + 1) / 2 - index) * STAT_LINE_H)
        line:SetWidth(STATS_W - 8)
        line:SetText(text)
        line:SetTextColor(r, g, b)
        line:Show()
    end
end

local function PlaceHeader(rowWidth)
    if not columnHeader then
        return
    end
    local levelX, statsX, slotX = Columns(rowWidth)
    local labels = columnHeader.labels
    labels.item:SetPoint("LEFT", columnHeader, "LEFT", 4 + 9, 0)
    labels.level:SetPoint("LEFT", columnHeader, "LEFT", 4 + levelX, 0)
    labels.stats:SetPoint("LEFT", columnHeader, "LEFT", 4 + statsX, 0)
    labels.slot:SetPoint("LEFT", columnHeader, "LEFT", 4 + slotX, 0)
end

-- Groups by the entry's source (raid boss, dungeon, or world source). Raid bosses follow the
-- Adventure Guide's boss order; everything else is alphabetical. Items inside a group are
-- ordered by slot, then name.
local function GroupItems(items, slot)
    local bossOrder = {}
    if type(slot) == "table" and type(slot.encounters) == "table" then
        for _, encounter in ipairs(slot.encounters) do
            if BGV.Utils.IsUsableNumber(encounter.uiOrder) then
                for _, id in ipairs({ encounter.journalEncounterID, encounter.dungeonEncounterID, encounter.activityEncounterID }) do
                    if BGV.Utils.IsUsableNumber(id) then
                        bossOrder[id] = encounter.uiOrder
                    end
                end
            end
        end
    end

    local groups = {}
    local byName = {}
    for _, entry in ipairs(items) do
        local name = entry.source or "Other"
        local group = byName[name]
        if not group then
            group = { name = name, entries = {} }
            byName[name] = group
            groups[#groups + 1] = group
        end
        local order = entry.encounterID and bossOrder[entry.encounterID]
        if order and (not group.order or order < group.order) then
            group.order = order
        end
        group.entries[#group.entries + 1] = entry
    end

    table.sort(groups, function(left, right)
        if left.order and right.order and left.order ~= right.order then
            return left.order < right.order
        end
        if (left.order ~= nil) ~= (right.order ~= nil) then
            return left.order ~= nil
        end
        return left.name < right.name
    end)
    for _, group in ipairs(groups) do
        table.sort(group.entries, function(left, right)
            local leftSlot, rightSlot = SlotName(left), SlotName(right)
            if leftSlot ~= rightSlot then
                return leftSlot < rightSlot
            end
            return (left.name or "") < (right.name or "")
        end)
    end
    return groups
end

local function AddGroupHeader(group, rowWidth, y)
    local row = Acquire()
    row:SetHeight(GROUP_H)
    row:SetWidth(rowWidth)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    row.entry = nil
    row.band:Show()
    row.bandEdge:Show()
    if row:GetHighlightTexture() then
        row:GetHighlightTexture():SetAlpha(0)
    end
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.name:SetWidth(rowWidth - 24)
    row.name:SetFontObject(GameFontNormal)
    row.name:SetText(string.format("%s  |cff8a8a8e%d|r", group.name, #group.entries))
    row.name:SetTextColor(0.95, 0.8, 0.45)
end

local function ShowMessage(text, rowWidth)
    local row = Acquire()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -8)
    row:SetWidth(rowWidth)
    row.entry = nil
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.name:SetWidth(rowWidth - 24)
    row.name:SetText(text)
    row.name:SetTextColor(0.55, 0.55, 0.58)
end

function Layout()
    if not child or not scroll then
        return
    end
    BGV.Utils.RefreshLootSpecButton(specButton)
    ReleaseRows()
    local model = BuildModel()
    local section = FindSection(model, selectedKey) or FirstSection(model, true)
    if section then
        selectedKey = section.id
    end
    if scroll.bgvKey ~= selectedKey then
        scroll:SetVerticalScroll(0)
        scroll.bgvKey = selectedKey
    end

    if rail then
        rail:SetShown(not solo)
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", solo and 16 or (LEFT_W + 16), -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    if not solo then
        PaintLinks(model)
    end
    if section then
        local items, pending = SlotItems(section.slot)
        section.items = items
        section.pending = pending
    end

    if headerTitle then
        local titleWidth = (frame:GetWidth() or 960) - (solo and 36 or (LEFT_W + 40))
        if titleWidth < 180 then
            titleWidth = 180
        end
        headerTitle:SetWidth(titleWidth)
        headerReward:SetWidth(titleWidth)
        if section then
            headerTitle:SetText(SlotTitle(section.slot))
            headerReward:SetText(RewardLine(section.slot))
        else
            headerTitle:SetText("Great Vault loot")
            headerReward:SetText("")
        end
    end

    local width = scroll:GetWidth()
    if not width or width < 160 then
        width = solo and 680 or 500
    end
    child:SetWidth(width)
    local rowWidth = width - 8
    PlaceHeader(rowWidth)
    local function Continue()
        if not section or not section.pending then
            ResetWatch()
            return
        end
        local mark = tostring(selectedKey) .. ":" .. tostring(#(section.items or {}))
        if mark ~= pendingWatch then
            pendingWatch = mark
            stalls = 0
            BGV.LootTable.RefreshPending()
            return
        end
        -- No progress this pass; poll a little later, and stop after ~10s of nothing new.
        -- A journal event (Nudge) or reopening the window starts it again.
        stalls = stalls + 1
        if stalls <= MAX_STALLS then
            BGV.LootTable.RefreshPending(POLL_DELAY)
        elseif stalls == MAX_STALLS + 1 and BetterGreatVaultDB and BetterGreatVaultDB.debug then
            BGV.Utils.Print(string.format("Loot table stopped waiting on %s (%d items so far): no new items for 10s.",
                SlotTitle(section.slot), #(section.items or {})))
            local trace = BGV.Rewards and type(BGV.Rewards.LastLoadTrace) == "function" and BGV.Rewards.LastLoadTrace()
            if trace then
                BGV.Utils.Print("Last load state: " .. trace)
            end
        end
    end
    if not section then
        ShowMessage("No Great Vault progress to list yet.", rowWidth)
        child:SetHeight(48)
        Continue()
        return
    end

    local items = section.items or {}
    if #items == 0 then
        if not section.slot.unlocked then
            ShowMessage("Locked.", rowWidth)
        elseif section.pending and stalls >= MAX_STALLS then
            ShowMessage("Loot didn't finish loading. Close and reopen this window to try again.", rowWidth)
        elseif section.pending then
            ShowMessage("Loading loot...", rowWidth)
        else
            ShowMessage("No items for this filter.", rowWidth)
        end
        child:SetHeight(48)
        Continue()
        return
    end

    local y = 2
    for groupIndex, group in ipairs(GroupItems(items, section.slot)) do
        if groupIndex > 1 then
            y = y + 6
        end
        AddGroupHeader(group, rowWidth, y)
        y = y + GROUP_H
        for index, entry in ipairs(group.entries) do
            local row = Acquire()
            row:SetWidth(rowWidth)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
            PlaceColumns(row, rowWidth)
            row.entry = entry
            row.icon:SetTexture(entry.icon)
            local r, g, b = QualityColor(entry)
            row.iconBG:SetVertexColor(r, g, b, 0.55)
            row.iconBG:Show()
            row.name:SetText(entry.name or "Item")
            row.name:SetTextColor(r, g, b)
            row.level:SetText(BGV.Utils.IsUsableNumber(entry.itemLevel) and tostring(entry.itemLevel) or "-")
            row.level:SetTextColor(0.96, 0.96, 0.96)
            row.slot:SetText(SlotName(entry))
            -- One stat per line, highest amount first; the row grows if there are more lines
            -- than fit.
            local stats = EntryStats(entry)
            local lines = {}
            for _, stat in ipairs(stats or NO_STATS) do
                local amount = type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(stat.amount) or tostring(stat.amount)
                lines[#lines + 1] = string.format("+%s %s", amount, stat.name)
            end
            if #lines > 0 then
                PaintStats(row, lines, 0.9, 0.9, 0.92)
            else
                PaintStats(row, { stats and "-" or "..." }, 0.55, 0.55, 0.58)
            end
            local height = math.max(ROW_H, #lines * STAT_LINE_H + 8)
            row:SetHeight(height)
            row.stripe:SetShown(index % 2 == 0)
            y = y + height
        end
    end
    child:SetHeight(math.max(y + 8, 40))
    Continue()
end

local function ApplyFilter(id, label)
    filterID = id
    if filterLabel then
        filterLabel:SetText(label)
    end
    if scroll then
        scroll:SetVerticalScroll(0)
    end
    Layout()
end

local function ApplyStatFilter()
    if statLabel then
        statLabel:SetText(StatFilterLabel())
    end
    if scroll then
        scroll:SetVerticalScroll(0)
    end
    Layout()
end

-- ids: list of "CRIT", "HASTE", "MASTERY", "VERSATILITY" (empty clears the filter).
function BGV.LootTable.SetStatFilter(ids)
    statFilter = {}
    for _, id in ipairs(ids or {}) do
        statFilter[id] = true
    end
    ApplyStatFilter()
end

local function Build()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "BetterGreatVaultLootTable", UIParent, "BackdropTemplate")
    frame:SetSize(960, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(760, 400, 1400, 900)
    end
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true,
            tileSize = 32,
            edgeSize = 24,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.06, 0.98)
        frame:SetBackdropBorderColor(0.85, 0.65, 0.2, 1)
    else
        Pixel(frame, "BACKGROUND", 0.07, 0.07, 0.08, 0.98):SetAllPoints()
    end

    local titleBar = Pixel(frame, "BORDER", 0, 0, 0, 0.22)
    titleBar:SetPoint("TOPLEFT", 8, -8)
    titleBar:SetPoint("TOPRIGHT", -8, -8)
    titleBar:SetHeight(34)
    local titleRule = Pixel(frame, "ARTWORK", 0.85, 0.65, 0.2, 0.8)
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleRule:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText("Great Vault loot")
    title:SetTextColor(0.85, 0.65, 0.2)

    local drag = CreateFrame("Button", nil, frame)
    drag:SetPoint("TOPLEFT")
    drag:SetPoint("TOPRIGHT", -180, 0)
    drag:SetHeight(40)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function()
        frame:StartMoving()
    end)
    drag:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
    end)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    local filter = CreateFrame("Button", "BetterGreatVaultLootTableFilter", frame, "UIPanelButtonTemplate")
    filter:SetSize(150, 22)
    filter:SetPoint("TOPRIGHT", -46, -12)
    filterLabel = filter.Text or _G[filter:GetName() .. "Text"]
    if filterLabel then
        filterLabel:SetText("All gear")
    end
    filter:SetScript("OnClick", function(self)
        if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
            MenuUtil.CreateContextMenu(self, function(_, root)
                for _, option in ipairs(FILTERS) do
                    root:CreateRadio(option.label, function()
                        return filterID == option.id
                    end, function()
                        ApplyFilter(option.id, option.label)
                    end)
                end
            end)
            return
        end
        local nextIndex = 1
        for index, option in ipairs(FILTERS) do
            if option.id == filterID then
                nextIndex = index % #FILTERS + 1
            end
        end
        ApplyFilter(FILTERS[nextIndex].id, FILTERS[nextIndex].label)
    end)

    -- Secondary stat filter: pick any number of stats. One shows items with it, two shows items
    -- with both, three or more shows items with at least one of them.
    local statButton = CreateFrame("Button", "BetterGreatVaultLootTableStats", frame, "UIPanelButtonTemplate")
    statButton:SetSize(150, 22)
    statButton:SetPoint("RIGHT", filter, "LEFT", -8, 0)
    statLabel = statButton.Text or _G[statButton:GetName() .. "Text"]
    if statLabel then
        statLabel:SetText(StatFilterLabel())
    end
    statButton:SetScript("OnClick", function(self)
        if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
            MenuUtil.CreateContextMenu(self, function(_, root)
                root:CreateTitle("Secondary stats")
                for _, stat in ipairs(SECONDARY_STATS) do
                    local id = stat.id
                    root:CreateCheckbox(StatName(stat), function()
                        return statFilter[id] == true
                    end, function()
                        statFilter[id] = not statFilter[id] or nil
                        ApplyStatFilter()
                        -- Keep the menu open so several stats can be picked in one go.
                        return MenuResponse and MenuResponse.Refresh or nil
                    end)
                end
                root:CreateDivider()
                root:CreateButton("Clear", function()
                    statFilter = {}
                    ApplyStatFilter()
                end)
            end)
            return
        end
        -- No menu API: cycle through no filter and each single stat.
        local selected = SelectedStats()
        local nextIndex = 1
        if #selected == 1 then
            for index, stat in ipairs(SECONDARY_STATS) do
                if stat == selected[1] then
                    nextIndex = index + 1
                end
            end
        end
        statFilter = {}
        if SECONDARY_STATS[nextIndex] then
            statFilter[SECONDARY_STATS[nextIndex].id] = true
        end
        ApplyStatFilter()
    end)

    specButton = BGV.Utils.CreateLootSpecButton(frame)
    specButton:SetPoint("RIGHT", statButton, "LEFT", -8, 0)

    -- The drag strip spans most of the title bar; keep the header buttons above it so
    -- clicks reach them instead of starting a window drag.
    filter:SetFrameLevel(drag:GetFrameLevel() + 2)
    statButton:SetFrameLevel(drag:GetFrameLevel() + 2)
    specButton:SetFrameLevel(drag:GetFrameLevel() + 2)

    rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -40)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    rail:SetWidth(LEFT_W)
    Pixel(rail, "BACKGROUND", 0, 0, 0, 0.18):SetAllPoints()
    local contents = rail:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    contents:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -12)
    contents:SetText("Contents")
    contents:SetTextColor(0.85, 0.65, 0.2)
    local divider = Pixel(frame, "BORDER", 0.22, 0.22, 0.24, 1)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 0)
    rail.divider = divider

    headerTitle = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    headerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 20, -46)
    headerTitle:SetJustifyH("LEFT")
    headerTitle:SetWordWrap(false)
    headerTitle:SetTextColor(0.96, 0.96, 0.96)
    headerReward = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    headerReward:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 0, -4)
    headerReward:SetJustifyH("LEFT")
    headerReward:SetWordWrap(false)
    headerReward:SetTextColor(1, 0.82, 0)
    local rule = Pixel(frame, "ARTWORK", 0.85, 0.65, 0.2, 0.9)
    rule:SetSize(36, 2)
    rule:SetPoint("TOPLEFT", headerReward, "BOTTOMLEFT", 0, -6)

    scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 16, -LIST_TOP)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    scroll:EnableMouseWheel(true)

    columnHeader = CreateFrame("Frame", nil, frame)
    columnHeader:SetHeight(24)
    columnHeader:SetPoint("BOTTOMLEFT", scroll, "TOPLEFT", 0, 4)
    columnHeader:SetPoint("BOTTOMRIGHT", scroll, "TOPRIGHT", 0, 4)
    Pixel(columnHeader, "BACKGROUND", 0, 0, 0, 0.35):SetAllPoints()
    local headerRule = Pixel(columnHeader, "ARTWORK", 0.85, 0.65, 0.2, 0.6)
    headerRule:SetHeight(1)
    headerRule:SetPoint("BOTTOMLEFT")
    headerRule:SetPoint("BOTTOMRIGHT")
    columnHeader.labels = {}
    for _, column in ipairs({ { "item", "Item" }, { "level", "Item Level" }, { "stats", "Secondary stats" }, { "slot", "Slot" } }) do
        local label = columnHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        label:SetText(column[2]:upper())
        label:SetTextColor(0.85, 0.65, 0.2)
        label:SetJustifyH("LEFT")
        columnHeader.labels[column[1]] = label
    end
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(520, 40)
    scroll:SetScrollChild(child)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local offset = self:GetVerticalScroll() - delta * 48
        local maxScroll = self:GetVerticalScrollRange()
        if offset < 0 then
            offset = 0
        end
        if offset > maxScroll then
            offset = maxScroll
        end
        self:SetVerticalScroll(offset)
    end)

    local sizer = CreateFrame("Button", nil, frame)
    sizer:SetSize(18, 18)
    sizer:SetPoint("BOTTOMRIGHT")
    local grip = sizer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    grip:SetPoint("CENTER")
    grip:SetText("..")
    grip:SetTextColor(0.45, 0.45, 0.48)
    sizer:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    sizer:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        Layout()
    end)

    frame:SetScript("OnShow", function()
        Layout()
    end)
    frame:RegisterEvent("CHALLENGE_MODE_MAPS_UPDATE")
    frame:RegisterEvent("EJ_LOOT_DATA_RECIEVED")
    frame:RegisterEvent("PLAYER_ENTERING_WORLD")
    frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    frame:RegisterEvent("PLAYER_LOOT_SPEC_UPDATED")
    frame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_ENTERING_WORLD" then
            BGV.LootTable.OnCharacterChanged()
            return
        end
        if event == "EJ_LOOT_DATA_RECIEVED" then
            -- Our own scans fire it too, with the journal changes they make.
            if not (BGV.Rewards and type(BGV.Rewards.IsScanning) == "function" and BGV.Rewards.IsScanning()) then
                BGV.LootTable.Nudge()
            end
            return
        end
        BGV.LootTable.Invalidate()
    end)

    if type(UISpecialFrames) == "table" then
        local listed = false
        for _, name in ipairs(UISpecialFrames) do
            if name == "BetterGreatVaultLootTable" then
                listed = true
                break
            end
        end
        if not listed then
            table.insert(UISpecialFrames, "BetterGreatVaultLootTable")
        end
    end
    return frame
end

if type(CloseWindows) == "function" and not BGV.LootTable.closeHooked then
    local originalCloseWindows = CloseWindows
    function CloseWindows(ignoreCenter, frameToIgnore)
        local loot = _G.BetterGreatVaultLootTable
        if loot and loot:IsShown() then
            loot:Hide()
            return 1
        end
        return originalCloseWindows(ignoreCenter, frameToIgnore)
    end
    BGV.LootTable.closeHooked = true
end

local function PlaceHeaders()
    if not headerTitle then
        return
    end
    headerTitle:ClearAllPoints()
    if solo then
        headerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -46)
        if rail and rail.divider then
            rail.divider:Hide()
        end
    else
        headerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 20, -46)
        if rail and rail.divider then
            rail.divider:Show()
        end
    end
end

function BGV.LootTable.Show(slot)
    local window = Build()
    itemCache = {}
    templateCache = {}
    ResetWatch()
    local category = CategoryFor(slot)
    solo = category ~= nil
    if category then
        selectedKey = SlotKey(category, slot)
    else
        selectedKey = nil
    end
    PlaceHeaders()
    window:Show()
    window:Raise()
    if scroll then
        scroll:SetVerticalScroll(0)
    end
    Layout()
end

function BGV.LootTable.ShowSlot(slot)
    if type(slot) ~= "table" or not slot.unlocked then
        return
    end
    BGV.LootTable.Show(slot)
end

function BGV.LootTable.Toggle()
    local window = Build()
    if window:IsShown() and not solo then
        window:Hide()
        return
    end
    BGV.LootTable.Show(nil)
end
