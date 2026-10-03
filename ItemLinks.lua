local _, BGV = ...

-- Item links at the exact item level a loot row shows (LootTable.lua): the link behind its tooltip
-- and the one Shift-click puts in chat. The vault's own reward link is the template, since its
-- bonuses carry the item level: bonuses come off one at a time, each try measured with C_Item,
-- until the link shows the level wanted, and then the row's item goes in.
BGV.ItemLinks = {}

local ItemLinks = BGV.ItemLinks
local Utils = BGV.Utils

-- Templates already worked out: "rewardLink@level" -> link (ItemLinks.Clear drops them).
local templateCache = {}

function ItemLinks.Clear()
    templateCache = {}
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
    local level = Utils.Call(C_Item.GetDetailedItemLevelInfo, link)
    if Utils.IsUsableNumber(level) and level > 0 then
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
    if not Utils.IsUsableNumber(entry.itemID) then
        return nil
    end
    if type(entry.rewardLink) == "string" and entry.rewardLink ~= "" and Utils.IsUsableNumber(entry.itemLevel) then
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

function ItemLinks.EntryLink(entry)
    if not entry.tipLink then
        entry.tipLink = TipLink(entry)
    end
    return entry.tipLink
end

-- The item's own chat link with `itemString` ("item:...") in it, so it shows that version.
local function FullLink(itemString, itemID)
    local _, link = Utils.Call(C_Item.GetItemInfo, itemID)
    if type(link) ~= "string" or link == "" then
        return nil
    end
    local body = type(itemString) == "string" and itemString:match("item:[^|]+")
    if not body then
        return link
    end
    return (link:gsub("item:[^|]+", function()
        return body
    end, 1))
end

-- The link Shift-click puts in chat: at the exact item level the row shows when the game can
-- give one (the vault reward's own bonuses, or the link behind the row's tooltip), measured
-- to be sure; else the item itself. Nil while the item's data loads.
function ItemLinks.ChatLink(entry)
    local itemID = entry.itemID
    if not (Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.GetItemInfo) == "function") then
        return nil
    end
    local want = entry.itemLevel
    if Utils.IsUsableNumber(want) then
        local candidate = ItemLinks.EntryLink(entry)
        if candidate and Measure(candidate) == want then
            return FullLink(candidate, itemID)
        end
        local info = C_TooltipInfo
        local data = info and type(info.GetItemKey) == "function" and Utils.Call(info.GetItemKey, itemID, want, 0)
        local hyperlink = type(data) == "table" and data.hyperlink
        if type(hyperlink) == "string" and not Utils.IsSecret(hyperlink) and Measure(hyperlink) == want then
            return hyperlink:find("|H", 1, true) and hyperlink or FullLink(hyperlink, itemID)
        end
    end
    return FullLink(nil, itemID)
end
