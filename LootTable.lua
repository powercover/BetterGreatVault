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

local CATEGORIES = {
    { id = "raid", title = "Raid", match = "Raid" },
    { id = "mplus", title = "Mythic+", match = "Activities" },
    { id = "world", title = "World", match = "World" },
}

local LEFT_W = 188

local frame
local rail
local scroll
local child
local headerTitle
local headerReward
local filterLabel
local specButton
local specLabel
local filterID = "ALL"
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
    if slot.unlocked and BGV.Rewards and type(BGV.Rewards.ItemsForSlot) == "function" then
        local found, stillLoading = BGV.Rewards.ItemsForSlot(slot)
        pending = stillLoading == true
        if type(found) == "table" then
            for _, entry in ipairs(found) do
                if filterID == "ALL" or entry.equipLabel == filterID then
                    list[#list + 1] = entry
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

function BGV.LootTable.Invalidate()
    itemCache = {}
    templateCache = {}
    pendingWatch = nil
    if BGV.Rewards and type(BGV.Rewards.InvalidateIcons) == "function" then
        BGV.Rewards.InvalidateIcons()
    end
    if frame and type(frame.IsShown) == "function" and frame:IsShown() then
        Layout()
    end
end

function BGV.LootTable.RefreshPending()
    if chunkQueued or not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        return
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    chunkQueued = true
    C_Timer.After(0, function()
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
    pendingWatch = nil
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
        row:SetHeight(32)
        row:RegisterForClicks("AnyUp")
        row.stripe = Pixel(row, "BACKGROUND", 1, 1, 1, 0.03)
        row.stripe:SetDrawLayer("BACKGROUND", -1)
        row.stripe:SetAllPoints()
        row.stripe:Hide()
        row.iconBG = Pixel(row, "BACKGROUND", 1, 1, 1, 1)
        row.iconBG:SetSize(28, 28)
        row.iconBG:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(24, 24)
        row.icon:SetPoint("LEFT", 8, 0)
        row.iconBG:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        row.text:SetPoint("LEFT", row.icon, "RIGHT", 8, 0)
        row.text:SetPoint("RIGHT", -8, 0)
        row.text:SetJustifyH("LEFT")
        row.text:SetWordWrap(false)
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
    row.stripe:Hide()
    row.iconBG:Hide()
    row:Show()
    return row
end

local function ReleaseRows()
    if not child then
        return
    end
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

function Layout()
    if not child or not scroll then
        return
    end
    if specButton then
        local shown = not BetterGreatVaultDB or BetterGreatVaultDB.showLootSpecButton ~= false
        specButton:SetShown(shown)
        if shown and specLabel then
            specLabel:SetText("Loot Spec: " .. BGV.Utils.LootSpecLabel())
        end
    end
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
    if solo then
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", 16, -100)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    else
        scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 16, -100)
        scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
        PaintLinks(model)
    end
    if section then
        local items, pending = SlotItems(section.slot)
        section.items = items
        section.pending = pending
    end

    if headerTitle then
        local titleWidth = (frame:GetWidth() or 860) - (solo and 36 or (LEFT_W + 40))
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
    local function Continue()
        if not section or not section.pending then
            pendingWatch = nil
            return
        end
        local mark = tostring(selectedKey) .. ":" .. tostring(#(section.items or {}))
        if mark == pendingWatch then
            return
        end
        pendingWatch = mark
        BGV.LootTable.RefreshPending()
    end
    if not section then
        local empty = Acquire()
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -8)
        empty:SetWidth(width - 8)
        empty.icon:SetTexture(nil)
        empty.entry = nil
        empty.text:SetText("No Great Vault progress to list yet.")
        empty.text:SetTextColor(0.55, 0.55, 0.58)
        child:SetHeight(48)
        Continue()
        return
    end

    local items = section.items or {}
    if #items == 0 then
        local empty = Acquire()
        empty:ClearAllPoints()
        empty:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -8)
        empty:SetWidth(width - 8)
        empty.icon:SetTexture(nil)
        empty.entry = nil
        if not section.slot.unlocked then
            empty.text:SetText("Locked.")
        elseif section.pending then
            empty.text:SetText("Loading loot...")
        else
            empty.text:SetText("No items for this filter.")
        end
        empty.text:SetTextColor(0.55, 0.55, 0.58)
        child:SetHeight(48)
        Continue()
        return
    end

    local grouped = CategoryFor(section.slot) and CategoryFor(section.slot).id == "mplus"
    local y = 4
    local rowIndex = 0
    local function AddItem(entry, indent)
        local row = Acquire()
        row:SetHeight(32)
        row:SetWidth(width - 8 - indent)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", child, "TOPLEFT", 4 + indent, -y)
        row.icon:SetSize(24, 24)
        row.icon:SetTexture(entry.icon)
        row.icon:SetVertexColor(1, 1, 1, 1)
        row.entry = entry
        if grouped then
            row.text:SetText(string.format("%s    %s", entry.name or "Item", entry.equipLabel or ""))
        else
            row.text:SetText(string.format("%s    %s    %s", entry.name or "Item", entry.equipLabel or "", entry.source or ""))
        end
        local r, g, b = QualityColor(entry)
        row.text:SetTextColor(r, g, b)
        row.iconBG:SetVertexColor(r, g, b, 0.55)
        row.iconBG:Show()
        rowIndex = rowIndex + 1
        row.stripe:SetShown(rowIndex % 2 == 0)
        y = y + 34
    end

    if grouped then
        local names = {}
        local byDungeon = {}
        for _, entry in ipairs(items) do
            local dungeon = entry.source or "Mythic+"
            if not byDungeon[dungeon] then
                byDungeon[dungeon] = {}
                names[#names + 1] = dungeon
            end
            byDungeon[dungeon][#byDungeon[dungeon] + 1] = entry
        end
        table.sort(names)
        for _, dungeon in ipairs(names) do
            local header = Acquire()
            header:SetHeight(26)
            header:SetWidth(width - 8)
            header:ClearAllPoints()
            header:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
            header.icon:SetSize(8, 8)
            header.icon:SetTexture("Interface\\Buttons\\WHITE8X8")
            header.icon:SetVertexColor(0.85, 0.65, 0.2, 1)
            header.entry = nil
            header.text:SetText(dungeon)
            header.text:SetTextColor(0.85, 0.65, 0.2)
            y = y + 28
            for _, entry in ipairs(byDungeon[dungeon]) do
                AddItem(entry, 22)
            end
        end
    else
        for _, entry in ipairs(items) do
            AddItem(entry, 0)
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
    Layout()
end

local function Build()
    if frame then
        return frame
    end
    frame = CreateFrame("Frame", "BetterGreatVaultLootTable", UIParent, "BackdropTemplate")
    frame:SetSize(860, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(640, 400, 1280, 900)
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

    specButton = CreateFrame("Button", "BetterGreatVaultLootTableSpec", frame, "UIPanelButtonTemplate")
    specButton:SetSize(180, 22)
    specButton:SetPoint("RIGHT", filter, "LEFT", -8, 0)
    specLabel = specButton.Text or _G[specButton:GetName() .. "Text"]
    specButton:SetScript("OnClick", function(self)
        if not BGV.Utils.OpenLootSpecMenu(self) then
            BGV.Utils.CycleLootSpec()
        end
    end)

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
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 16, -100)
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    scroll:EnableMouseWheel(true)
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
            BGV.LootTable.Nudge()
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
