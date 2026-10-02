local _, BGV = ...

BGV.LootTable = {}

local L = BGV.L

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
local NAME_X = 40

-- Sizes that follow the text size setting (Utils.FontOffset), set by UpdateMetrics before each
-- layout: row and line heights grow with the text, and the text columns widen with it.
local LIST_TOP, ROW_H, TIER_W, LEVEL_W, STATS_W, SLOT_W, GROUP_H, STAT_LINE_H
local SOURCE_H, HEADER_H, LINK_H, SOURCE_ROW_H, SOURCE_GAP

local function UpdateMetrics()
    local offset = BGV.Utils.FontOffset()
    local scale = BGV.Utils.FontScale(10)
    LIST_TOP = 132 + 2 * offset
    ROW_H = 30 + offset
    TIER_W = 44 + offset
    LEVEL_W = math.floor(80 * scale + 0.5)
    STATS_W = math.floor(150 * scale + 0.5)
    SLOT_W = math.floor(130 * scale + 0.5)
    GROUP_H = 26 + offset
    STAT_LINE_H = 12 + offset
    SOURCE_H = 22 + offset
    HEADER_H = 24 + offset
    LINK_H = 28 + offset
    SOURCE_ROW_H = 54 + 2 * offset
    SOURCE_GAP = 8
end

UpdateMetrics()

-- Column x offsets within a row of the given width; the header uses the same geometry.
-- Without Best-in-Slot tiers (settings) the Tier column takes no room.
local function Columns(width)
    local slotX = width - SLOT_W - 8
    local statsX = slotX - STATS_W
    local levelX = statsX - LEVEL_W
    local tierX = BGV.Utils.ShowBisTiers() and levelX - TIER_W or levelX
    return tierX, levelX, statsX, slotX
end

-- Best-in-Slot tier letters (Bis.lua), coloured like the reels' tier backgrounds.
local TIER_RANK = { S = 5, A = 4, B = 3, C = 2, D = 1 }
local TIER_TEXT = {
    S = { 1, 0.78, 0.2 },
    A = { 0.78, 0.45, 1 },
    B = { 0.4, 0.62, 1 },
    C = { 0.35, 0.85, 0.4 },
    D = { 0.62, 0.62, 0.64 },
}

local frame
local rail
local columnHeader
local scroll
local child
local headerTitle
local headerReward
local gearFilterButton
local statFilterButton
local searchBox
local specButton
local filterID = "ALL"
-- The item name search (lower case, trimmed); empty lists everything.
local searchText = ""
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
local RefreshHeaderFilters
local pendingWatch
local chunkQueued

-- The list as lines, top to bottom (Layout): a source's divider, a group's header, an item or a
-- message, each with its place (y) and height. Only the lines in view get a row (PaintVisible),
-- so a long list costs no more to draw than a short one, and scrolling paints the rows that come
-- into view. `painted` maps a line's index to its row.
local lines, lineCount = {}, 0
local painted = {}
local paintedFirst, paintedLast
local listWidth
local paintTiers, paintSpecs
-- When the list was last laid out (GetTime), to pace the redraws while it loads.
local lastLayoutAt
-- The loot table's own timing for /bgv perf (BGV.LootTable.lastLoad): the redraws from opening
-- or changing the list until it has loaded, their time in all and the longest.
local loading

-- Smooth scrolling (like the settings panel): the mouse wheel sets a target the list eases to.
-- `tipWaiting`: a row came under the pointer while the list moved (see ListMoving).
local scrollTarget
local tipWaiting = false
local UpdateScrollThumb

local function JumpScroll(offset)
    scrollTarget = nil
    tipWaiting = false
    if scroll then
        scroll:SetVerticalScroll(offset or 0)
    end
    if UpdateScrollThumb then
        UpdateScrollThumb()
    end
end

-- "vault": the Great Vault's own slots. "database" (Shift+middle-click on the minimap button):
-- everything the vault can award this season, as if everything were completed, for any class
-- and spec, at the vault's item level for a chosen difficulty, keystone level or world tier.
local mode = "vault"
-- "tier": the class set pieces, which any vault slot can award, listed once here rather than
-- under every source, at the item level of a level picked from the other sources.
local DB_SOURCES = {
    { id = "tier", title = "Tier set", header = "Tier set", order = 0 },
    { id = "raid", title = "Raid", header = "Raid", order = 1 },
    { id = "mplus", title = "M+ keystones", header = "Mythic+", order = 2 },
    { id = "world", title = "World", header = "World", order = 3 },
}
-- The tier source's level menu heads each source's levels with its name.
local TIER_FROM_TITLES = { raid = "Raid", mplus = "Mythic+", world = "World" }
-- The database's choices, kept for the session: the sources listed (any number, never none;
-- the tier set, Raid and M+ to start with), the level per source, class and spec (classID 0:
-- all classes; specID 0: all of the class's specs).
local db = { sources = { tier = true, raid = true, mplus = true }, levels = {} }
local classButton
local windowTitle
local railTitle
local dbRows = {}

local Pixel = BGV.Utils.Pixel

-- The addon's accent color (settings: the spec's color or a custom one), on the window's lines,
-- bars, scroll indicator, active filters and row hover. Text keeps its own colors.
local accentColor = { 0.85, 0.65, 0.2 }
local accentTextures = {}

local function Accent(texture, alpha)
    accentTextures[#accentTextures + 1] = { texture = texture, alpha = alpha or 1 }
    texture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], alpha or 1)
    return texture
end

-- Dark text on a light accent, light text on a dark one.
local function OnAccentText()
    local luminance = 0.299 * accentColor[1] + 0.587 * accentColor[2] + 0.114 * accentColor[3]
    if luminance > 0.5 then
        return 0.07, 0.07, 0.08
    end
    return 1, 1, 1
end

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
    local title = string.format(L["Slot %s"], tostring(slot.index or "?"))
    if BGV.Utils.IsUsableNumber(slot.threshold) and type(slot.unit) == "string" then
        title = string.format("%s • %d %s", title, slot.threshold, slot.unit)
    end
    if type(slot.qualifier) == "string" and slot.qualifier ~= "" then
        title = title .. " • " .. slot.qualifier
    end
    if not slot.unlocked then
        title = title .. " • " .. L["Locked"]
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
        return string.format(L["%s %d/%d (%d ilvl)"], slot.upgradeTrack, slot.upgradeLevel, slot.upgradeMax, slot.itemLevel)
    end
    if BGV.Utils.IsUsableNumber(slot.itemLevel) then
        return string.format(L["%d ilvl"], slot.itemLevel)
    end
    return ""
end

local function StatName(stat)
    local text = _G[stat.global]
    if type(text) == "string" and text ~= "" then
        return text
    end
    return L[stat.name]
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

-- Tooltip reads for items whose stats aren't cached yet, per redraw (reset by Layout): at most
-- this many, and no more once they've taken STAT_BUDGET_MS, so a large list of uncached items
-- fills in over a few redraws instead of stalling one frame.
local STAT_LOOKUPS_PER_PASS = 40
local STAT_BUDGET_MS = 2
local statLookups = STAT_LOOKUPS_PER_PASS
local statSpent = 0
-- Whether the redraw left stats unread because it had read its share, so the next redraw can
-- come as soon as it may (see Layout's Continue).
local statsCut = false

-- The stat cache's key for an entry, kept on it: every redraw looks up every entry's stats.
local function StatKey(entry)
    local key = entry.bgvStatKey
    if not key then
        key = tostring(entry.itemID) .. ":" .. tostring(entry.itemLevel)
        entry.bgvStatKey = key
    end
    return key
end

-- The item's stats if already read (see EntryStats), without reading them. Once known they're
-- kept on the entry too: every redraw asks for every entry's.
local function CachedStats(entry)
    local known = entry.bgvStats
    if known then
        return known
    end
    local info = C_TooltipInfo
    if not (info and type(info.GetItemKey) == "function") or not BGV.Utils.IsUsableNumber(entry.itemID) then
        return NO_STATS
    end
    known = statCache[StatKey(entry)]
    entry.bgvStats = known
    return known
end

-- The item's secondary stats at the level the vault awards, read from the same tooltip the row
-- shows (C_TooltipInfo.GetItemKey, the data behind GameTooltip:SetItemKey), highest amount
-- first. Returns nil while the item's tooltip data hasn't loaded.
local function EntryStats(entry)
    local known = CachedStats(entry)
    if known then
        return known
    end
    local info = C_TooltipInfo
    local key = StatKey(entry)
    if statLookups <= 0 or statSpent >= STAT_BUDGET_MS then
        statsCut = true
        return nil
    end
    statLookups = statLookups - 1
    local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
    local data
    if BGV.Utils.IsUsableNumber(entry.itemLevel) then
        data = BGV.Utils.Call(info.GetItemKey, entry.itemID, entry.itemLevel, 0)
    elseif type(info.GetItemByID) == "function" then
        data = BGV.Utils.Call(info.GetItemByID, entry.itemID)
    end
    if started then
        statSpent = statSpent + (debugprofilestop() - started)
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
    entry.bgvStats = stats
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

-- The first letter of the stat's (localized) name, for the header's filter button.
local function StatLetter(stat)
    local name = StatName(stat)
    return name:match("^[\1-\127\194-\244][\128-\191]*") or L[stat.short]:sub(1, 1)
end

-- What the stat filter shows, for the filter button's tooltip.
local function StatFilterSummary()
    local selected = SelectedStats()
    if #selected == 0 then
        return L["Showing all items"]
    end
    local names = {}
    for _, stat in ipairs(selected) do
        names[#names + 1] = StatName(stat)
    end
    if #selected == 1 then
        return string.format(L["Items with %s"], names[1])
    elseif #selected == 2 then
        return string.format(L["Items with both %s and %s"], names[1], names[2])
    end
    return string.format(L["Items with at least one of: %s"], table.concat(names, ", "))
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
        searchText,
    }, ":")
end

-- The gear and stat filters. An item whose stats are still loading is listed (without stats)
-- unless filtering by stat, and the list stays pending so it's redrawn once they arrive.
local function MatchesSearch(entry)
    if searchText == "" then
        return true
    end
    return type(entry.name) == "string" and entry.name:lower():find(searchText, 1, true) ~= nil
end

local function FilterEntries(found)
    local list = {}
    local pending = false
    local selected = SelectedStats()
    for _, entry in ipairs(type(found) == "table" and found or {}) do
        if (filterID == "ALL" or entry.equipLabel == filterID) and MatchesSearch(entry) then
            if #selected == 0 then
                -- Stats only show here: Layout reads them in the order the list shows them.
                list[#list + 1] = entry
                pending = pending or CachedStats(entry) == nil
            else
                local stats = EntryStats(entry)
                if not stats then
                    pending = true
                elseif PassesStatFilter(stats, selected) then
                    list[#list + 1] = entry
                end
            end
        end
    end
    return list, pending
end

local function FiltersActive()
    return filterID ~= "ALL" or #SelectedStats() > 0 or searchText ~= ""
end

-- Why a filtered list is empty: nothing matches what was searched for, or the filters.
local function NoMatchText()
    local otherFilters = filterID ~= "ALL" or #SelectedStats() > 0
    if searchText ~= "" and otherFilters then
        return L["No items match the search and filters."]
    elseif searchText ~= "" then
        local typed = BGV.Utils.Trim(searchBox and searchBox:GetText() or searchText)
        return string.format(L["No items match \"%s\"."], (typed:gsub("|", "||")))
    end
    return L["No items match these filters."]
end

local function SlotItems(slot)
    local key = CacheKey(slot)
    local cached = itemCache[key]
    if cached then
        return cached, false
    end
    local found
    local pending = false
    if slot.unlocked and BGV.Rewards and type(BGV.Rewards.ItemsForSlot) == "function" then
        local stillLoading
        found, stillLoading = BGV.Rewards.ItemsForSlot(slot)
        pending = stillLoading == true
    end
    local list, statsPending = FilterEntries(found)
    if pending or statsPending then
        return list, true
    end
    itemCache[key] = list
    return list, false
end

-- The selected sources, in rail order (never none).
local function SelectedSources()
    local list = {}
    for _, source in ipairs(DB_SOURCES) do
        if db.sources[source.id] then
            list[#list + 1] = source
        end
    end
    if #list == 0 then
        db.sources[DB_SOURCES[1].id] = true
        list[1] = DB_SOURCES[1]
    end
    return list
end

-- The chosen level of a database source ({ level, label, itemLevel, ceiling }); the source's
-- default when none is chosen yet.
local function DatabaseLevel(sourceID)
    local levels = BGV.Rewards and type(BGV.Rewards.DatabaseLevels) == "function" and BGV.Rewards.DatabaseLevels(sourceID) or {}
    local chosen, fallback
    for _, info in ipairs(levels) do
        if info.level == db.levels[sourceID] then
            chosen = info
        end
        if info.level == levels.default then
            fallback = info
        end
    end
    if chosen and chosen.itemLevel then
        return chosen
    end
    -- Nothing chosen yet, or its item level isn't known (any more): the default, a known one.
    if fallback then
        db.levels[sourceID] = fallback.level
        return fallback
    end
    return chosen
end

local function ItemLevelText(info)
    if not (info and info.itemLevel) then
        return nil
    end
    if info.ceiling then
        return string.format("%d/%d", info.itemLevel, info.ceiling)
    end
    return tostring(info.itemLevel)
end

local function DatabaseKey(sourceID)
    return table.concat({
        "database",
        tostring(sourceID),
        tostring(db.levels[sourceID]),
        tostring(db.classID),
        tostring(db.specID),
        tostring(filterID),
        StatFilterKey(),
        searchText,
    }, ":")
end

-- One source's list, filtered; entries carry the source's order so groups stay per source.
-- `budget` (Rewards.NewReadBudget) is the journal reading time the sources share in one redraw.
local function DatabaseItems(source, budget)
    local key = DatabaseKey(source.id)
    local cached = itemCache[key]
    if cached then
        return cached, false
    end
    local found
    local pending = false
    if BGV.Rewards and type(BGV.Rewards.DatabaseItems) == "function" then
        local stillLoading
        found, stillLoading = BGV.Rewards.DatabaseItems(source.id, db.levels[source.id], db.classID, db.specID, budget)
        pending = stillLoading == true
        -- A redraw that read the journal leaves the item stats to the next one, so no redraw does
        -- both of the heavy jobs.
        if budget and budget.reads > 0 then
            statLookups = 0
        end
    end
    local list, statsPending = FilterEntries(found)
    for _, entry in ipairs(list) do
        entry.sourceOrder = source.order
    end
    if pending or statsPending then
        return list, true
    end
    itemCache[key] = list
    return list, false
end

local function ClassInfo(classID)
    for _, class in ipairs(BGV.Utils.Classes()) do
        if class.id == classID then
            return class
        end
    end
end

local function AllClassesText()
    return BGV.Utils.GameText("ALL_CLASSES", "All classes")
end

local function ClassSpecLabel()
    if db.classID == 0 then
        return AllClassesText()
    end
    local class = ClassInfo(db.classID)
    if not class then
        return BGV.Utils.GameText("CLASS", "Class")
    end
    local specName = L["All specs"]
    if BGV.Utils.IsUsableNumber(db.specID) and db.specID ~= 0 then
        for _, spec in ipairs(BGV.Utils.ClassSpecs(db.classID)) do
            if spec.id == db.specID then
                specName = spec.name
            end
        end
    end
    return BGV.Utils.ClassColorText(class.file, class.name) .. ": " .. specName
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
-- Rewards dropped just the batches that can now complete (Rewards.RetryGivenUp). Items load in
-- bursts, so the redraw waits for the next loading pass rather than coming once per item.
function BGV.LootTable.Reload()
    itemCache = {}
    templateCache = {}
    ResetWatch()
    BGV.LootTable.RefreshPending()
end

function BGV.LootTable.RefreshPending(delay)
    if chunkQueued or not frame or type(frame.IsShown) ~= "function" or not frame:IsShown() then
        return
    end
    if not (C_Timer and type(C_Timer.After) == "function") then
        return
    end
    -- While a list loads, it's redrawn at most this often (seconds): item data arrives in bursts
    -- of events, and each redraw reads the journal again.
    local PASS_GAP = 0.1
    local wait = delay or 0
    if lastLayoutAt and type(GetTime) == "function" then
        wait = math.max(wait, PASS_GAP - (GetTime() - lastLayoutAt))
    end
    chunkQueued = true
    C_Timer.After(wait, function()
        chunkQueued = false
        if frame and frame:IsShown() then
            Layout(true)
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
                    title = string.format(L["Slot %s"], tostring(slot.index or "?")),
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

-- The item's own chat link with `itemString` ("item:...") in it, so it shows that version.
local function FullLink(itemString, itemID)
    local _, link = BGV.Utils.Call(C_Item.GetItemInfo, itemID)
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
local function ChatLink(entry)
    local itemID = entry.itemID
    if not (BGV.Utils.IsUsableNumber(itemID) and C_Item and type(C_Item.GetItemInfo) == "function") then
        return nil
    end
    local want = entry.itemLevel
    if BGV.Utils.IsUsableNumber(want) then
        local candidate = EntryLink(entry)
        if candidate and Measure(candidate) == want then
            return FullLink(candidate, itemID)
        end
        local info = C_TooltipInfo
        local data = info and type(info.GetItemKey) == "function" and BGV.Utils.Call(info.GetItemKey, itemID, want, 0)
        local hyperlink = type(data) == "table" and data.hyperlink
        if type(hyperlink) == "string" and not BGV.Utils.IsSecret(hyperlink) and Measure(hyperlink) == want then
            return hyperlink:find("|H", 1, true) and hyperlink or FullLink(hyperlink, itemID)
        end
    end
    return FullLink(nil, itemID)
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
end

-- Comparisons with the equipped items follow the game, as over the vault's own items: while the
-- compare key (Shift) is held, or always with "Always compare items". The game's tooltip rules
-- add them to the tooltip FillTooltip sets.
local function ShouldCompare()
    return TooltipUtil and type(TooltipUtil.ShouldDoItemComparison) == "function"
        and TooltipUtil.ShouldDoItemComparison(GameTooltip) == true or false
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

-- The class set's bonuses as tooltip lines, worded as the game's own tooltip words them: a spec's
-- name, then its bonuses ("(4) Set: ..." before they're active on you, "Set: ..." once they are).
-- Whose: in a vault slot's list, the loot spec's (the Great Vault's loot spec button); in the
-- database, the chosen spec's, or every spec of the class (All specs, All classes). Returns the
-- lines ({ text, r, g, b }), whether a bonus's text is still loading and the set's name, or nil.
local function BonusLines(classID)
    if not (BGV.Rewards and type(BGV.Rewards.SetBonuses) == "function") then
        return nil
    end
    local specs = {}
    if mode ~= "database" then
        specs[1] = BGV.Utils.LootSpecID()
    elseif BGV.Utils.IsUsableNumber(db.specID) and db.specID > 0 then
        specs[1] = db.specID
    else
        for _, spec in ipairs(BGV.Utils.ClassSpecs(classID)) do
            specs[#specs + 1] = spec.id
        end
    end
    local lines, pending, name = {}, false, nil
    for _, specID in ipairs(specs) do
        local bonuses = BGV.Rewards.SetBonuses(classID, specID)
        if bonuses then
            name = name or bonuses.name
            local specName = BGV.Utils.LootSpecName(specID)
            if specName then
                lines[#lines + 1] = { text = specName, r = 1, g = 1, b = 1 }
            end
            for _, line in ipairs(bonuses.lines) do
                lines[#lines + 1] = line
            end
            if #bonuses.lines == 0 then
                lines[#lines + 1] = { text = "...", r = 0.55, g = 0.55, b = 0.58 }
            end
            pending = pending or bonuses.pending
        end
    end
    if #lines == 0 then
        return nil
    end
    return lines, pending, name
end

if TooltipDataProcessor and type(TooltipDataProcessor.AddTooltipPostCall) == "function" and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
        if tooltip ~= GameTooltip then
            return
        end
        local owner = tooltip:GetOwner()
        if not (owner and owner.bgvLootRow and owner.entry) then
            return
        end
        PaintTitle(tooltip, owner.entry)
        -- A tooltip by item level has no spec, so for a set piece the game writes "Bonus effects
        -- vary based on the player's specialization." where the set's bonuses go: the bonuses
        -- (BonusLines) go there instead.
        owner.bgvBonusPending = nil
        local lines, pending
        if owner.entry.tierClass and BGV.Utils.IsUsableString(ITEM_SET_BONUS_NO_VALID_SPEC) then
            lines, pending = BonusLines(owner.entry.tierClass)
        end
        if not lines then
            return
        end
        owner.bgvBonusPending = pending or nil
        for index = 1, tooltip:NumLines() do
            local left = _G[tooltip:GetName() .. "TextLeft" .. index]
            local text = left and left:GetText()
            if BGV.Utils.IsUsableString(text) and text == ITEM_SET_BONUS_NO_VALID_SPEC then
                local parts = {}
                for _, line in ipairs(lines) do
                    parts[#parts + 1] = string.format("|cff%02x%02x%02x%s|r", math.floor(line.r * 255 + 0.5),
                        math.floor(line.g * 255 + 0.5), math.floor(line.b * 255 + 0.5), line.text)
                end
                left:SetText(table.concat(parts, "\n"))
                tooltip:Show()
                return
            end
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
    owner.bgvCompare = ShouldCompare()
    if Item and type(Item.CreateFromItemID) == "function" then
        local item = BGV.Utils.Call(Item.CreateFromItemID, Item, entry.itemID)
        if item and type(item.IsItemDataCached) == "function" and not item:IsItemDataCached() and type(item.ContinueOnLoad) == "function" then
            item:ContinueOnLoad(function()
                if owner:IsShown() and owner:IsMouseOver() and owner.entry == entry then
                    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
                    FillTooltip(entry)
                    PaintTitle(GameTooltip, entry)
                    owner.bgvCompare = ShouldCompare()
                end
            end)
        end
    end
end

-- The tier set header's tooltip: the set's name and the bonuses its pieces' tooltips show
-- (BonusLines).
local function ShowSetBonusTooltip(row)
    local lines, pending, name
    if row.bgvTierClass then
        lines, pending, name = BonusLines(row.bgvTierClass)
    end
    row.bgvBonusPending = pending or nil
    if not lines or not GameTooltip then
        return
    end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:AddLine(name or L["Tier set"], 1, 0.82, 0)
    for _, line in ipairs(lines) do
        GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
    end
    GameTooltip:Show()
end

-- The game calls this every 0.2s while a row owns the tooltip (GameTooltip_OnUpdate): pressing
-- or letting go of the compare key shows or hides the comparisons. It stands in for the game's
-- own refresh of changed tooltip data, so that's passed on.
local function UpdateRowTooltip(row)
    if not row.entry then
        -- The tier set header: its bonuses' text arrives a moment after the first hover.
        if row.bgvBonusPending then
            ShowSetBonusTooltip(row)
        end
        return
    end
    -- A set piece whose bonuses' text was still loading: its tooltip again, now with them.
    if row.bgvBonusPending then
        ShowItemTooltip(row, row.entry)
        return
    end
    if GameTooltip.shouldRefreshData and type(GameTooltip.RefreshData) == "function" then
        GameTooltip:RefreshData()
        row.bgvCompare = ShouldCompare()
        return
    end
    local compare = ShouldCompare()
    if compare == row.bgvCompare then
        return
    end
    row.bgvCompare = compare
    if compare and type(GameTooltip_ShowCompareItem) == "function" then
        GameTooltip_ShowCompareItem(GameTooltip)
    elseif not compare and type(GameTooltip_HideShoppingTooltips) == "function" then
        GameTooltip_HideShoppingTooltips(GameTooltip)
    end
end

-- While the list scrolls, rows slide under the pointer one after another, and each would build
-- an item tooltip (with its comparisons, the costliest thing the loot table does). Their
-- tooltips wait instead, and the row under the pointer gets its tooltip once the list has
-- nearly stopped (the scroll's OnUpdate): within SETTLING_PX of where it's going.
local function ListMoving()
    local SETTLING_PX = 8
    return scrollTarget ~= nil and math.abs(scrollTarget - (scroll:GetVerticalScroll() or 0)) > SETTLING_PX
end

-- The row the pointer is on: the one that gets mouse events there (not one merely beneath a
-- menu covering the list).
local function UnderPointer(row)
    if row.IsMouseMotionFocus then
        return row:IsMouseMotionFocus()
    end
    return row:IsMouseOver()
end

local function ShowTipUnderPointer()
    tipWaiting = false
    if not scroll:IsMouseOver() then
        return
    end
    for _, row in pairs(painted) do
        if row.entry and UnderPointer(row) then
            ShowItemTooltip(row, row.entry)
            return
        elseif row.bgvTierClass and UnderPointer(row) then
            ShowSetBonusTooltip(row)
            return
        end
    end
end

local function Acquire()
    local row = table.remove(pool)
    if not row then
        row = CreateFrame("Button", nil, child)
        row.bgvLootRow = true
        row:RegisterForClicks("AnyUp")
        row.stripe = Pixel(row, "BACKGROUND", 1, 1, 1, 0.025)
        row.stripe:SetDrawLayer("BACKGROUND", -1)
        row.stripe:SetAllPoints()
        row.stripe:Hide()
        row.band = Pixel(row, "BACKGROUND", 1, 1, 1, 0.05)
        row.band:SetDrawLayer("BACKGROUND", -1)
        row.band:SetAllPoints()
        row.band:Hide()
        row.bandEdge = Pixel(row, "ARTWORK", 0.85, 0.65, 0.2, 0.95)
        row.bandEdge:SetWidth(2)
        row.bandEdge:SetPoint("TOPLEFT")
        row.bandEdge:SetPoint("BOTTOMLEFT")
        row.bandEdge:Hide()
        -- A 1px quality-coloured edge around the icon (the icon's own border cropped away).
        row.iconBG = Pixel(row, "BACKGROUND", 1, 1, 1, 1)
        row.iconBG:SetSize(24, 24)
        row.iconBG:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(22, 22)
        row.icon:SetPoint("LEFT", 9, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconBG:SetPoint("CENTER", row.icon, "CENTER", 0, 0)
        -- The Tier column's coloured badge, with the letter on it.
        row.tierBadge = Pixel(row, "ARTWORK", 1, 1, 1, 1)
        row.tierBadge:SetSize(20, 16)
        row.tierBadge:Hide()

        row.name = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
        row.name:SetJustifyH("LEFT")
        row.name:SetWordWrap(false)
        row.tier = BGV.Utils.FontString(row, "OVERLAY", "NormalSmall")
        row.tier:SetJustifyH("CENTER")
        row.tier:SetWordWrap(false)
        row.level = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
        row.level:SetJustifyH("LEFT")
        row.level:SetWordWrap(false)
        row.slot = BGV.Utils.FontString(row, "OVERLAY", "HighlightSmall")
        row.slot:SetJustifyH("LEFT")
        row.slot:SetWordWrap(false)
        -- One font string per secondary stat, stacked (see PaintStats).
        row.statLines = {}

        -- Hover: a light accent wash in the HIGHLIGHT layer. (A Button's own highlight texture is
        -- drawn additively and ignores its alpha, which turned rows solid white.)
        row.hover = Pixel(row, "HIGHLIGHT", 1, 1, 1, 0.12)
        row.hover:SetAllPoints()
        row:SetScript("OnEnter", function(self)
            if ListMoving() then
                tipWaiting = true
                return
            end
            if self.entry then
                ShowItemTooltip(self, self.entry)
            else
                ShowSetBonusTooltip(self)
            end
        end)
        row.UpdateTooltip = UpdateRowTooltip
        row:SetScript("OnLeave", function(self)
            if GameTooltip and GameTooltip:GetOwner() == self then
                GameTooltip:Hide()
            end
        end)
        row:SetScript("OnClick", function(self, button)
            -- Shift-click links the item in chat, Ctrl-click previews it, like the game's items.
            if button == "LeftButton" and IsModifiedClick() and self.entry and type(HandleModifiedItemClick) == "function" then
                local link = ChatLink(self.entry)
                if link then
                    HandleModifiedItemClick(link)
                elseif C_Item and type(C_Item.RequestLoadItemDataByID) == "function" then
                    C_Item.RequestLoadItemDataByID(self.entry.itemID)
                end
            end
        end)
    end
    row:SetHeight(ROW_H)
    row.bgvTierClass, row.bgvBonusPending = nil, nil
    row.stripe:Hide()
    row.band:Hide()
    row.bandEdge:Hide()
    row.iconBG:Hide()
    row.tierBadge:Hide()
    row.hover:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 0.12)
    row.hover:Show()
    row.bandEdge:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 0.95)
    row.icon:SetTexture(nil)
    row.name:SetFontObject(BGV.Utils.Font("Highlight"))
    row.name:SetText("")
    row.tier:SetText("")
    row.level:SetText("")
    row.slot:SetText("")
    row.slot:SetTextColor(0.7, 0.7, 0.72)
    for _, line in ipairs(row.statLines) do
        line:SetText("")
        line:Hide()
    end
    row:Show()
    return row
end

-- Puts a painted row back in the pool. A row is either painted (in `painted`) or pooled, never
-- both, so none is handed out twice.
local function ReleaseRow(index)
    local row = painted[index]
    painted[index] = nil
    row:Hide()
    row.entry = nil
    pool[#pool + 1] = row
end

local function ReleaseRows()
    for index in pairs(painted) do
        ReleaseRow(index)
    end
    paintedFirst, paintedLast = nil, nil
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
            link.hover = Pixel(link, "HIGHLIGHT", 1, 1, 1, 0.05)
            link.hover:SetAllPoints()
            local bar = Accent(Pixel(link, "ARTWORK", 1, 1, 1, 1))
            bar:SetSize(2, 14)
            bar:SetPoint("LEFT", link, "LEFT", 0, 0)
            bar:Hide()
            link.bar = bar
            local label = BGV.Utils.FontString(link, "OVERLAY", "Highlight")
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
        link:SetHeight(LINK_H)
        link:Show()
        return link
    end

    local y = 36
    for _, group in ipairs(model) do
        local header = Take()
        header.kind = "header"
        header.selected = false
        header:SetScript("OnClick", nil)
        header.hover:Hide()
        header:ClearAllPoints()
        header:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -y)
        header:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -y)
        header.bar:Hide()
        header.underline:Hide()
        header.label:SetText(L[group.title])
        header.label:SetTextColor(0.85, 0.65, 0.2)
        y = y + LINK_H
        for _, section in ipairs(group.slots) do
            local link = Take()
            local selected = section.id == selectedKey
            link.kind = "slot"
            link.selected = selected
            link.hover:Show()
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
            y = y + LINK_H
        end
        y = y + 8
    end
end

-- The slot's name in the game's language, kept on the entry: sorting a list asks for it on
-- every comparison.
local function SlotName(entry)
    local name = entry.bgvSlotName
    if name then
        return name
    end
    local label = type(entry.equipLoc) == "string" and _G[entry.equipLoc]
    name = type(label) == "string" and label ~= "" and label or entry.equipLabel or ""
    entry.bgvSlotName = name
    return name
end

-- Armor type (Cloth, Leather, Mail, Plate, or Shield) by itemID; false when the item has none
-- that matters (jewelry, trinkets, cloaks, weapons).
local armorTypes = {}
local WEARABLE_ARMOR = { [1] = true, [2] = true, [3] = true, [4] = true }

local function ArmorType(entry)
    local itemID = entry.itemID
    if not BGV.Utils.IsUsableNumber(itemID) or type(GetItemInfoInstant) ~= "function" then
        return nil
    end
    local known = armorTypes[itemID]
    if known ~= nil then
        return known or nil
    end
    local _, _, subType, equipLoc, _, classID, subClassID = GetItemInfoInstant(itemID)
    if not BGV.Utils.IsUsableNumber(classID) then
        return nil
    end
    local armorClass = Enum and Enum.ItemClass and Enum.ItemClass.Armor or 4
    local shield = Enum and Enum.ItemArmorSubclass and Enum.ItemArmorSubclass.Shield or 6
    local text = false
    if classID == armorClass then
        if subClassID == shield then
            text = L["Shield"]
        elseif WEARABLE_ARMOR[subClassID] and equipLoc ~= "INVTYPE_CLOAK" and type(subType) == "string" and subType ~= "" then
            text = subType
        end
    end
    armorTypes[itemID] = text
    return text or nil
end

-- The Slot column: the slot, with the armor type where it matters ("Head (Plate)").
local function SlotText(entry)
    local slot = SlotName(entry)
    local armor = ArmorType(entry)
    if armor then
        return string.format("%s (%s)", slot, armor)
    end
    return slot
end

-- The highest Best-in-Slot tier the item has for any of `specs` (nil: none, or no specs).
local function BestTier(itemID, specs)
    if not (BGV.Bis and type(BGV.Bis.Tier) == "function") or not BGV.Utils.IsUsableNumber(itemID) then
        return nil
    end
    local best
    for _, specID in ipairs(specs) do
        local tier = BGV.Bis.Tier(itemID, specID)
        if tier and TIER_RANK[tier] and (not best or TIER_RANK[tier] > TIER_RANK[best]) then
            best = tier
        end
    end
    return best
end

-- Whose Best-in-Slot tier the Tier column shows: the loot spec (as the reels do), or in the
-- database the chosen spec, the best among the chosen class's specs, or nobody for all classes.
local function TierSpecs()
    if mode ~= "database" then
        local specID = BGV.Utils.LootSpecID()
        return specID and { specID } or {}
    end
    if BGV.Utils.IsUsableNumber(db.specID) and db.specID > 0 then
        return { db.specID }
    end
    local specs = {}
    if BGV.Utils.IsUsableNumber(db.classID) and db.classID > 0 then
        for _, spec in ipairs(BGV.Utils.ClassSpecs(db.classID)) do
            specs[#specs + 1] = spec.id
        end
    end
    return specs
end

local function PlaceColumns(row, rowWidth)
    local tierX, levelX, statsX, slotX = Columns(rowWidth)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", NAME_X, 0)
    row.name:SetWidth(math.max(40, tierX - NAME_X - 10))
    row.tierBadge:ClearAllPoints()
    row.tierBadge:SetPoint("LEFT", row, "LEFT", tierX, 0)
    row.tierBadge:SetSize(20 + BGV.Utils.FontOffset(), 16 + BGV.Utils.FontOffset())
    row.tier:ClearAllPoints()
    row.tier:SetPoint("CENTER", row.tierBadge, "CENTER", 0, 0)
    row.tier:SetWidth(TIER_W - 8)
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
            line = BGV.Utils.FontString(row, "OVERLAY", "HighlightSmall")
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

-- The width of a font string's text on one line, whatever width the string is set to.
local function TextWidth(fontString)
    local width = fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth()
    if type(width) ~= "number" then
        width = fontString:GetStringWidth()
    end
    return math.ceil(width or 0)
end

-- Fits a column's label, and the filter button after it, into `room`. Translations run longer
-- than English: a label too long for its column is cut short with "..." (the full name shows
-- on hover), and a long filter pick on the button takes at most 60% of the room.
local function FitHeaderColumn(label, room, button)
    local buttonRoom = 0
    if button then
        local width = math.max(16, math.min(TextWidth(button.text) + 8, math.floor(room * 0.6)))
        button:SetWidth(width)
        button.text:SetWidth(width - 8)
        buttonRoom = width + 5
    end
    label:SetWidth(math.max(12, math.min(TextWidth(label), room - buttonRoom)))
end

local function PlaceHeader(rowWidth)
    if not columnHeader then
        return
    end
    local tierX, levelX, statsX, slotX = Columns(rowWidth)
    local labels = columnHeader.labels
    labels.item:SetPoint("LEFT", columnHeader, "LEFT", 4 + 9, 0)
    labels.tier:SetPoint("LEFT", columnHeader, "LEFT", 4 + tierX, 0)
    labels.tier:SetShown(BGV.Utils.ShowBisTiers())
    labels.tier.hover:SetShown(BGV.Utils.ShowBisTiers())
    labels.level:SetPoint("LEFT", columnHeader, "LEFT", 4 + levelX, 0)
    labels.stats:SetPoint("LEFT", columnHeader, "LEFT", 4 + statsX, 0)
    labels.slot:SetPoint("LEFT", columnHeader, "LEFT", 4 + slotX, 0)
    -- The header's controls follow the text size; each label keeps to its column, like the rows.
    local offset = BGV.Utils.FontOffset()
    for _, button in ipairs({ statFilterButton, gearFilterButton }) do
        button:SetHeight(16 + offset)
    end
    FitHeaderColumn(labels.tier, TIER_W - 8)
    FitHeaderColumn(labels.level, LEVEL_W - 8)
    FitHeaderColumn(labels.stats, STATS_W - 8, statFilterButton)
    FitHeaderColumn(labels.slot, SLOT_W - 8, gearFilterButton)
    -- The search box fits between the Item label and the Tier column, at least 50 wide.
    FitHeaderColumn(labels.item, tierX - 9 - 8 - (searchBox and 66 or 0))
    if searchBox then
        local left = 9 + labels.item:GetWidth() + 6
        local room = tierX - left - 10
        local width = math.floor(150 * BGV.Utils.FontScale(10) + 0.5)
        searchBox:SetSize(math.max(50, math.min(width, room)), 16 + offset)
    end
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
        local name = entry.source or L["Other"]
        local key = tostring(entry.sourceOrder or 0) .. ":" .. name
        local group = byName[key]
        if not group then
            group = { name = name, entries = {}, sourceOrder = entry.sourceOrder or 0 }
            byName[key] = group
            groups[#groups + 1] = group
        end
        local order = entry.encounterID and bossOrder[entry.encounterID] or entry.bossOrder
        if order and (not group.order or order < group.order) then
            group.order = order
        end
        group.entries[#group.entries + 1] = entry
    end

    table.sort(groups, function(left, right)
        if left.sourceOrder ~= right.sourceOrder then
            return left.sourceOrder < right.sourceOrder
        end
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

-- The last grouping, reused while a redraw lists the very same entries in the same order (one
-- that only brought stats, say): grouping sorts the whole list.
local grouped = {}

local function SameEntries(list, other)
    if not other or #list ~= #other then
        return false
    end
    for index = 1, #list do
        if list[index] ~= other[index] then
            return false
        end
    end
    return true
end

local function Groups(items, slot)
    if grouped.groups and grouped.slot == slot and SameEntries(items, grouped.items) then
        return grouped.groups
    end
    grouped.items, grouped.slot, grouped.groups = items, slot, GroupItems(items, slot)
    return grouped.groups
end

-- A group's header. The tier set's (its pieces carry their class) shows the set's bonuses when
-- hovered (ShowSetBonusTooltip).
local function AddGroupHeader(group, rowWidth, y)
    local row = Acquire()
    row:SetHeight(GROUP_H)
    row:SetWidth(rowWidth)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    row.entry = nil
    row.bgvTierClass = group.entries[1] and group.entries[1].tierClass or nil
    row.band:Show()
    row.bandEdge:Show()
    row.hover:Hide()
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.name:SetWidth(rowWidth - 24)
    row.name:SetFontObject(BGV.Utils.Font("Normal"))
    row.name:SetText(string.format("%s   |cff77777b%d|r", group.name, #group.entries))
    row.name:SetTextColor(0.96, 0.86, 0.6)
    return row
end


-- Heads one source's groups when several sources are listed: "RAID • MYTHIC • 334/344".
local function AddSourceHeader(text, rowWidth, y)
    local row = Acquire()
    row.hover:Hide()
    row:SetHeight(SOURCE_H)
    row:SetWidth(rowWidth)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    row.entry = nil
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 2, 0)
    row.name:SetWidth(rowWidth - 8)
    row.name:SetFontObject(BGV.Utils.Font("NormalSmall"))
    row.name:SetText(BGV.Utils.Upper(text))
    row.name:SetTextColor(accentColor[1], accentColor[2], accentColor[3])
    return row
end

local function ShowMessage(text, rowWidth, y)
    local row = Acquire()
    row.hover:Hide()
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -y)
    row:SetWidth(rowWidth)
    row.entry = nil
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", 12, 0)
    row.name:SetWidth(rowWidth - 24)
    row.name:SetText(text)
    row.name:SetTextColor(0.55, 0.55, 0.58)
    return row
end

-- One item's row: icon, name, tier, item level, secondary stats (one a line, highest amount
-- first) and slot. The row is as tall as its stats need (see Layout).
local function PaintItem(line)
    local entry = line.entry
    local row = Acquire()
    row:SetWidth(listWidth)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", child, "TOPLEFT", 4, -line.y)
    PlaceColumns(row, listWidth)
    row.entry = entry
    row.icon:SetTexture(entry.icon)
    local r, g, b = QualityColor(entry)
    row.iconBG:SetVertexColor(r, g, b, 0.9)
    row.iconBG:Show()
    row.name:SetText(entry.name or L["Item"])
    row.name:SetTextColor(r, g, b)
    local tier = paintTiers and BestTier(entry.itemID, paintSpecs) or nil
    if tier then
        local color = TIER_TEXT[tier]
        row.tierBadge:SetVertexColor(color[1], color[2], color[3], 0.95)
        row.tierBadge:Show()
        row.tier:SetText(tier)
        row.tier:SetTextColor(0.07, 0.07, 0.08)
    else
        row.tier:SetText(paintTiers and "-" or "")
        row.tier:SetTextColor(0.45, 0.45, 0.48)
    end
    row.level:SetText(BGV.Utils.IsUsableNumber(entry.itemLevel) and tostring(entry.itemLevel) or "-")
    row.level:SetTextColor(0.96, 0.96, 0.96)
    row.slot:SetText(SlotText(entry))
    local stats = line.stats
    local exact = BGV.Utils.IsUsableNumber(entry.itemLevel)
    local texts = {}
    for _, stat in ipairs(stats or NO_STATS) do
        if exact then
            local amount = type(BreakUpLargeNumbers) == "function" and BreakUpLargeNumbers(stat.amount) or tostring(stat.amount)
            texts[#texts + 1] = string.format("+%s %s", amount, stat.name)
        else
            -- The amounts depend on an item level that isn't known here.
            texts[#texts + 1] = stat.name
        end
    end
    if #texts > 0 then
        PaintStats(row, texts, 0.9, 0.9, 0.92)
    else
        PaintStats(row, { stats and "-" or "..." }, 0.55, 0.55, 0.58)
    end
    row:SetHeight(line.height)
    row.stripe:SetShown(line.index % 2 == 0)
    return row
end

local function PaintLine(line)
    if line.kind == "item" then
        return PaintItem(line)
    elseif line.kind == "group" then
        return AddGroupHeader(line.group, listWidth, line.y)
    elseif line.kind == "source" then
        return AddSourceHeader(line.text, listWidth, line.y)
    end
    return ShowMessage(line.text, listWidth, line.y)
end

-- What a row shows, so a redraw while the list loads can keep a row that would look the same.
local function Remember(row, line)
    local entry, group = line.entry, line.group
    row.bgvKind, row.bgvY, row.bgvHeight, row.bgvText, row.bgvStats = line.kind, line.y, line.height, line.text, line.stats
    row.bgvWidth = listWidth
    row.bgvItem = entry and entry.itemID
    row.bgvItemLevel = entry and entry.itemLevel
    row.bgvName = entry and entry.name
    row.bgvIcon = entry and entry.icon
    row.bgvQuality = entry and entry.quality
    row.bgvStripe = line.index and line.index % 2 == 0
    row.bgvGroup = group and group.name
    row.bgvCount = group and #group.entries
end

local function StillShows(row, line)
    local entry, group = line.entry, line.group
    return row.bgvKind == line.kind and row.bgvY == line.y and row.bgvHeight == line.height
        and row.bgvText == line.text and row.bgvStats == line.stats and row.bgvWidth == listWidth
        and row.bgvItem == (entry and entry.itemID) and row.bgvItemLevel == (entry and entry.itemLevel)
        and row.bgvName == (entry and entry.name) and row.bgvIcon == (entry and entry.icon)
        and row.bgvQuality == (entry and entry.quality) and row.bgvStripe == (line.index and line.index % 2 == 0)
        and row.bgvGroup == (group and group.name) and row.bgvCount == (group and #group.entries)
end

-- Adds a line below the others; the line tables are reused from one layout to the next.
local function AddLine(kind, y, height)
    lineCount = lineCount + 1
    local line = lines[lineCount]
    if not line then
        line = {}
        lines[lineCount] = line
    end
    line.kind, line.y, line.height = kind, y, height
    line.entry, line.index, line.stats, line.group, line.text = nil, nil, nil, nil, nil
    return line
end

local function ViewHeight()
    local height = scroll:GetHeight()
    if type(height) ~= "number" or height < 40 then
        -- Not laid out yet: the list's place in the window (see Layout).
        height = (frame and frame:GetHeight() or 560) - LIST_TOP - 16
    end
    return height
end

-- Gives the lines in view a row, and takes rows back from lines scrolled out of view. Called by
-- Layout and whenever the list scrolls or resizes. `recheck`: the lines are new but rows were
-- kept (a redraw while loading), so repaint only the rows that no longer show their line.
local function PaintVisible(recheck)
    -- A hidden window paints nothing; showing it lays it out (OnShow).
    if not (scroll and child and listWidth and frame:IsVisible()) then
        return
    end
    if lineCount == 0 then
        ReleaseRows()
        return
    end
    -- Painted beyond the visible area, so rows are ready before they scroll into view.
    local OVERSCAN = 64
    local top = scroll:GetVerticalScroll() or 0
    local from, to = top - OVERSCAN, top + ViewHeight() + OVERSCAN
    -- The first line reaching below `from` (lines are in order, top to bottom), then every line
    -- starting above `to`.
    local low, high = 1, lineCount
    while low < high do
        local middle = math.floor((low + high) / 2)
        local line = lines[middle]
        if line.y + line.height <= from then
            low = middle + 1
        else
            high = middle
        end
    end
    local first, last = low, low
    while last < lineCount and lines[last + 1].y < to do
        last = last + 1
    end
    if not recheck and first == paintedFirst and last == paintedLast then
        return
    end
    for index, row in pairs(painted) do
        if index < first or index > last or (recheck and not StillShows(row, lines[index])) then
            ReleaseRow(index)
        elseif recheck then
            -- The same item, maybe in a new copy: tooltips and clicks use the current one.
            row.entry = lines[index].entry
            local group = lines[index].kind == "group" and lines[index].group
            row.bgvTierClass = group and group.entries[1] and group.entries[1].tierClass or nil
        end
    end
    for index = first, last do
        if not painted[index] then
            local row = PaintLine(lines[index])
            Remember(row, lines[index])
            painted[index] = row
        end
    end
    paintedFirst, paintedLast = first, last
end

-- The vault mode's section: one Great Vault slot.
local function VaultSection(model)
    local section = FindSection(model, selectedKey) or FirstSection(model, true)
    if not section then
        return nil
    end
    selectedKey = section.id
    local items, pending = SlotItems(section.slot)
    return {
        key = section.id,
        title = SlotTitle(section.slot),
        reward = RewardLine(section.slot),
        items = items,
        pending = pending,
        locked = not section.slot.unlocked,
        slot = section.slot,
    }
end

local function DatabaseRewardLine(info)
    if not (info and info.itemLevel) then
        return L["Vault item level not known yet"]
    end
    if info.ceiling then
        return string.format(L["Vault reward: %d item level, %d from the raid's last two bosses"], info.itemLevel, info.ceiling)
    end
    return string.format(L["Vault reward: %d item level"], info.itemLevel)
end

-- A source with its chosen level: "Raid • Mythic", "Mythic +7" / "Mythic +10+", "World • Tier 8".
local function SourceName(source, info)
    if not info then
        return L[source.header]
    end
    if source.id == "mplus" then
        return string.format(L["Mythic %s"], info.label)
    end
    return L[source.header] .. " • " .. info.label
end

-- How many instances the last redraw read from the journal (DatabaseSection's budget).
local passReads = 0

-- The database mode's section: every selected source at its chosen level, for the chosen class
-- and spec. A source whose item level isn't known yet lists nothing rather than items at a
-- guessed one. With several sources, `parts` heads each source's groups in the list.
local function DatabaseSection()
    -- The journal reading time (ms) all the sources share in one redraw: a source still loading
    -- reads the rest on the next redraws, so opening the database doesn't stall a frame.
    local DB_READ_MS = 3
    local budget = BGV.Rewards and type(BGV.Rewards.NewReadBudget) == "function" and BGV.Rewards.NewReadBudget(DB_READ_MS) or nil
    local sources = SelectedSources()
    local keys = { "database", tostring(db.classID), tostring(db.specID) }
    local titles, rewards, parts = {}, {}, {}
    local items, pending, known = {}, false, 0
    for _, source in ipairs(sources) do
        local info = DatabaseLevel(source.id)
        local name = SourceName(source, info)
        keys[#keys + 1] = source.id .. "=" .. tostring(info and info.level)
        titles[#titles + 1] = name
        parts[#parts + 1] = { order = source.order, text = name .. " • " .. (ItemLevelText(info) or L["item level not known yet"]) }
        if info and info.itemLevel then
            known = known + 1
            local list, sourcePending = DatabaseItems(source, budget)
            pending = pending or sourcePending
            for _, entry in ipairs(list) do
                items[#items + 1] = entry
            end
            if info.ceiling then
                rewards[#rewards + 1] = string.format(L["%s %d (%d from the last two bosses)"], L[source.header], info.itemLevel, info.ceiling)
            else
                rewards[#rewards + 1] = string.format("%s %d", L[source.header], info.itemLevel)
            end
        else
            rewards[#rewards + 1] = string.format(L["%s not known yet"], L[source.header])
        end
    end
    passReads = budget and budget.reads or 0
    local section = {
        key = table.concat(keys, ":"),
        title = table.concat(titles, "  +  "),
        items = items,
        pending = pending,
        locked = false,
        database = true,
        unknownLevel = known == 0,
        parts = #sources > 1 and parts or nil,
    }
    if #sources == 1 then
        section.reward = DatabaseRewardLine(DatabaseLevel(sources[1].id))
    else
        section.reward = string.format(L["Vault reward: %s"], table.concat(rewards, "  •  "))
    end
    return section
end

local function PaintDatabaseRail()
    for _, link in ipairs(linkRows) do
        link:Hide()
    end
    local y = 36
    for _, source in ipairs(DB_SOURCES) do
        local row = dbRows[source.id]
        if row then
            local selected = db.sources[source.id] == true
            local info = DatabaseLevel(source.id)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -y)
            row:SetPoint("TOPRIGHT", rail, "TOPRIGHT", -8, -y)
            row:SetHeight(SOURCE_ROW_H)
            row.level:ClearAllPoints()
            row.level:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -(SOURCE_ROW_H - 28))
            row.level:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            row.level:SetHeight(20 + BGV.Utils.FontOffset())
            row.bar:SetShown(selected)
            row.fill:SetShown(selected)
            -- The level picker only works for a listed source.
            row.level:SetEnabled(selected)
            row.level:SetAlpha(selected and 1 or 0.35)
            row.label:SetText(L[source.title])
            if selected then
                row.label:SetTextColor(0.96, 0.96, 0.96)
            else
                row.label:SetTextColor(0.46, 0.46, 0.48)
            end
            local levelText = info and info.label or L["Item level unknown"]
            local itemLevel = ItemLevelText(info)
            if itemLevel then
                levelText = levelText .. " • " .. itemLevel
            elseif info then
                levelText = levelText .. " • " .. L["unknown"]
            end
            row.level:SetText(levelText)
            row:Show()
        end
        y = y + SOURCE_ROW_H + SOURCE_GAP
    end
end

local function HideDatabaseRail()
    for _, row in pairs(dbRows) do
        row:Hide()
    end
end

local function PaintAccent()
    local color = BGV.Utils and type(BGV.Utils.AccentColor) == "function" and BGV.Utils.AccentColor()
    if type(color) == "table" then
        accentColor = color
    end
    for _, item in ipairs(accentTextures) do
        item.texture:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], item.alpha)
    end
    RefreshHeaderFilters()
end

local function RefreshModeWidgets()
    local database = mode == "database"
    if windowTitle then
        windowTitle:SetText(database and L["Loot database"] or L["Great Vault loot"])
    end
    if railTitle then
        railTitle:SetText(database and L["Loot sources"] or L["Contents"])
    end
    if database then
        if specButton then
            specButton:Hide()
        end
        if classButton then
            classButton:SetText(ClassSpecLabel())
            classButton:Show()
        end
    else
        if classButton then
            classButton:Hide()
        end
        BGV.Utils.RefreshLootSpecButton(specButton)
    end
end

-- Adds a redraw that took from `started` until now to the load it's part of: a redraw while
-- loading (`keepRows`) continues the load, any other starts a new one.
local function NoteRedraw(started, keepRows, pending)
    if not started then
        return
    end
    local spent = debugprofilestop() - started
    if not (keepRows and loading) then
        loading = { redraws = 0, time = 0, peak = 0 }
    end
    loading.redraws = loading.redraws + 1
    loading.time = loading.time + spent
    loading.peak = math.max(loading.peak, spent)
    if not pending then
        BGV.LootTable.lastLoad = loading
        loading = nil
    end
end

-- `keepRows`: a redraw while the list loads (RefreshPending), which keeps the rows that would
-- look the same; any other redraw paints every row in view anew.
function Layout(keepRows)
    if not child or not scroll then
        return
    end
    local started = type(debugprofilestop) == "function" and debugprofilestop() or nil
    lastLayoutAt = type(GetTime) == "function" and GetTime() or nil
    local database = mode == "database"
    statLookups = STAT_LOOKUPS_PER_PASS
    statSpent = 0
    statsCut = false
    passReads = 0
    UpdateMetrics()
    PaintAccent()
    RefreshModeWidgets()
    -- The old lines go first, so scrolling back to the top below paints none of them.
    lineCount = 0
    if not keepRows then
        ReleaseRows()
    end
    local model, section
    if database then
        section = DatabaseSection()
    else
        model = BuildModel()
        section = VaultSection(model)
    end
    local key = section and section.key or selectedKey
    if scroll.bgvKey ~= key then
        JumpScroll(0)
        scroll.bgvKey = key
    end

    local showRail = database or not solo
    if rail then
        rail:SetShown(showRail)
    end
    scroll:ClearAllPoints()
    scroll:SetPoint("TOPLEFT", frame, "TOPLEFT", showRail and (LEFT_W + 16) or 16, -LIST_TOP)
    if columnHeader then
        columnHeader:SetHeight(HEADER_H)
    end
    scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -16, 16)
    if database then
        PaintDatabaseRail()
    else
        HideDatabaseRail()
        if not solo then
            PaintLinks(model)
        end
    end

    if headerTitle then
        local titleWidth = (frame:GetWidth() or 1000) - (showRail and (LEFT_W + 40) or 36)
        if titleWidth < 180 then
            titleWidth = 180
        end
        headerTitle:SetWidth(titleWidth)
        headerReward:SetWidth(titleWidth)
        if section then
            headerTitle:SetText(section.title)
            headerReward:SetText(section.reward or "")
        else
            headerTitle:SetText(L["Great Vault loot"])
            headerReward:SetText("")
        end
    end

    local width = scroll:GetWidth()
    if not width or width < 160 then
        width = solo and 680 or 500
    end
    child:SetWidth(width)
    local rowWidth = width - 8
    listWidth = rowWidth
    PlaceHeader(rowWidth)
    local function Continue()
        NoteRedraw(started, keepRows, section and section.pending)
        if not section or not section.pending then
            ResetWatch()
            return
        end
        -- Progress: new items, or a redraw that stopped reading (the journal or stats) because it
        -- had read its share.
        local mark = tostring(key) .. ":" .. tostring(#(section.items or {}))
        if mark ~= pendingWatch or statsCut or passReads > 0 then
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
                section.title, #(section.items or {})))
            local trace = BGV.Rewards and type(BGV.Rewards.LastLoadTrace) == "function" and BGV.Rewards.LastLoadTrace()
            if trace then
                BGV.Utils.Print("Last load state: " .. trace)
            end
        end
    end
    local function Message(text)
        AddLine("message", 8, ROW_H).text = text
        child:SetHeight(48)
        PaintVisible(keepRows)
        Continue()
    end
    if not section then
        Message(L["No Great Vault progress to list yet."])
        return
    end

    local items = section.items or {}
    if #items == 0 then
        if section.locked then
            Message(L["Locked."])
        elseif section.unknownLevel then
            Message(L["The vault hasn't shown item levels for this yet. Complete one of these in your Great Vault this season and they'll appear here."])
        elseif section.pending and stalls >= MAX_STALLS then
            Message(L["Loot didn't finish loading. Close and reopen this window to try again."])
        elseif section.pending then
            -- Filters may still match items whose data hasn't arrived yet.
            Message(FiltersActive() and L["Nothing matches so far. Still loading loot..."] or L["Loading loot..."])
        elseif FiltersActive() then
            Message(NoMatchText())
        elseif section.database then
            Message(L["No loot found here for this class."])
        else
            Message(L["No loot found for this slot."])
        end
        return
    end

    paintTiers = BGV.Utils.ShowBisTiers()
    paintSpecs = TierSpecs()
    local y = 2
    local function AddGroup(group, first)
        if not first then
            y = y + 6
        end
        AddLine("group", y, GROUP_H).group = group
        y = y + GROUP_H
        for index, entry in ipairs(group.entries) do
            -- One stat a line (PaintItem): the row grows if there are more lines than fit.
            local stats = EntryStats(entry)
            local height = math.max(ROW_H, #(stats or NO_STATS) * STAT_LINE_H + 8)
            local line = AddLine("item", y, height)
            line.entry, line.index, line.stats = entry, index, stats
            y = y + height
        end
    end
    local groups = Groups(items, section.slot)
    if section.parts then
        -- Several database sources: each source's groups under its own divider.
        for partIndex, part in ipairs(section.parts) do
            if partIndex > 1 then
                y = y + 12
            end
            AddLine("source", y, SOURCE_H).text = part.text
            y = y + SOURCE_H
            local first = true
            for _, group in ipairs(groups) do
                if group.sourceOrder == part.order then
                    AddGroup(group, first)
                    first = false
                end
            end
        end
    else
        for groupIndex, group in ipairs(groups) do
            AddGroup(group, groupIndex == 1)
        end
    end
    child:SetHeight(math.max(y + 8, 40))
    PaintVisible(keepRows)
    Continue()
end

-- The small filter buttons in the column header: "+" while nothing is picked, else a short
-- summary of the pick on a gold fill, so an active filter stands out.
local function PaintHeaderFilter(button, text, active)
    if not button then
        return
    end
    button.text:SetText(text)
    button:SetWidth(math.max(16, TextWidth(button.text) + 8))
    if active then
        button.back:SetVertexColor(accentColor[1], accentColor[2], accentColor[3], 0.95)
        button.text:SetTextColor(OnAccentText())
    else
        button.back:SetVertexColor(0.24, 0.24, 0.26, 0.95)
        button.text:SetTextColor(0.85, 0.65, 0.2)
    end
end

local function GearFilterLabel()
    for _, option in ipairs(FILTERS) do
        if option.id == filterID then
            return L[option.label]
        end
    end
    return L[FILTERS[1].label]
end

function RefreshHeaderFilters()
    PaintHeaderFilter(gearFilterButton, filterID == "ALL" and "+" or GearFilterLabel(), filterID ~= "ALL")
    local letters = {}
    for _, stat in ipairs(SelectedStats()) do
        letters[#letters + 1] = StatLetter(stat)
    end
    PaintHeaderFilter(statFilterButton, #letters > 0 and table.concat(letters) or "+", #letters > 0)
end

local function ApplyFilter(id)
    filterID = id
    RefreshHeaderFilters()
    JumpScroll(0)
    Layout()
end

local function ApplyStatFilter()
    RefreshHeaderFilters()
    JumpScroll(0)
    Layout()
end

local function OpenGearMenu(anchor)
    if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle(L["Gear"])
            for _, option in ipairs(FILTERS) do
                root:CreateRadio(L[option.label], function()
                    return filterID == option.id
                end, function()
                    ApplyFilter(option.id)
                end)
            end
        end)
        return
    end
    -- No menu API: step to the next slot.
    local nextIndex = 1
    for index, option in ipairs(FILTERS) do
        if option.id == filterID then
            nextIndex = index % #FILTERS + 1
        end
    end
    ApplyFilter(FILTERS[nextIndex].id)
end

-- Pick any number of stats: one shows items with it, two items with both, three or more items
-- with at least one of them.
local function OpenStatMenu(anchor)
    if MenuUtil and type(MenuUtil.CreateContextMenu) == "function" then
        MenuUtil.CreateContextMenu(anchor, function(_, root)
            root:CreateTitle(L["Secondary stats"])
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
            root:CreateButton(L["Clear"], function()
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
end

local function CreateHeaderFilter(label, onClick, describe)
    local button = CreateFrame("Button", nil, columnHeader)
    button:SetHeight(16)
    button:SetPoint("LEFT", label, "RIGHT", 5, 0)
    button.back = Pixel(button, "BACKGROUND", 0.24, 0.24, 0.26, 0.95)
    button.back:SetAllPoints()
    local shine = Pixel(button, "HIGHLIGHT", 1, 1, 1, 0.18)
    shine:SetAllPoints()
    button.text = BGV.Utils.FontString(button, "OVERLAY", "NormalSmall")
    button.text:SetPoint("CENTER", button, "CENTER", 0, 0)
    button.text:SetWordWrap(false)
    button:SetScript("OnClick", onClick)
    button:SetScript("OnEnter", function(self)
        if GameTooltip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            describe(GameTooltip)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function()
        if GameTooltip then
            GameTooltip:Hide()
        end
    end)
    return button
end

local function ScrollTop()
    JumpScroll(0)
end

-- The item name search, in the column header after the Item label like the other filters. The
-- list redraws a moment after typing stops, not on every letter.
local function CreateSearchBox(label)
    local box = CreateFrame("EditBox", nil, columnHeader)
    box:SetSize(150, 16)
    box:SetPoint("LEFT", label, "RIGHT", 6, 0)
    box:SetAutoFocus(false)
    box:SetMaxLetters(40)
    box:SetFontObject(BGV.Utils.Font("HighlightSmall"))
    box:SetTextInsets(6, 16, 0, 0)
    box.back = Pixel(box, "BACKGROUND", 0.24, 0.24, 0.26, 0.95)
    box.back:SetAllPoints()
    box.rule = Accent(Pixel(box, "ARTWORK", 1, 1, 1, 1))
    box.rule:SetHeight(1)
    box.rule:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT", 0, 0)
    box.rule:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)
    box.rule:Hide()
    box.hint = BGV.Utils.FontString(box, "OVERLAY", "HighlightSmall")
    box.hint:SetPoint("LEFT", box, "LEFT", 6, 0)
    box.hint:SetText(L["Search"])
    box.hint:SetTextColor(0.55, 0.55, 0.58)
    local clear = CreateFrame("Button", nil, box)
    clear:SetSize(14, 14)
    clear:SetPoint("RIGHT", box, "RIGHT", -1, 0)
    for _, angle in ipairs({ 45, -45 }) do
        local line = Pixel(clear, "ARTWORK", 0.72, 0.72, 0.75, 1)
        line:SetSize(8, 1)
        line:SetPoint("CENTER", clear, "CENTER", 0, 0)
        if line.SetRotation then
            line:SetRotation(math.rad(angle))
        end
    end
    clear:Hide()
    clear:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)
    box.clear = clear

    local token = 0
    local function Redraw()
        JumpScroll(0)
        Layout()
    end
    box:SetScript("OnTextChanged", function(self)
        local typed = self:GetText() or ""
        self.hint:SetShown(typed == "" and not self:HasFocus())
        clear:SetShown(typed ~= "")
        self.rule:SetShown(typed ~= "")
        local text = BGV.Utils.Trim(typed):lower()
        if text == searchText then
            return
        end
        searchText = text
        token = token + 1
        local mine = token
        if C_Timer and type(C_Timer.After) == "function" then
            C_Timer.After(0.25, function()
                if mine == token then
                    Redraw()
                end
            end)
        else
            Redraw()
        end
    end)
    box:SetScript("OnEditFocusGained", function(self)
        self.hint:Hide()
    end)
    box:SetScript("OnEditFocusLost", function(self)
        self.hint:SetShown((self:GetText() or "") == "")
    end)
    box:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    box:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)
    return box
end

-- Clicking a source toggles it; clicking the only selected one leaves it selected.
local function ToggleDatabaseSource(sourceID)
    if db.sources[sourceID] then
        local selected = 0
        for _, source in ipairs(DB_SOURCES) do
            if db.sources[source.id] then
                selected = selected + 1
            end
        end
        if selected <= 1 then
            return
        end
        db.sources[sourceID] = nil
    else
        db.sources[sourceID] = true
    end
    ResetWatch()
    ScrollTop()
    Layout()
end

local function SetDatabaseClass(classID, specID)
    db.classID = classID
    db.specID = specID or 0
    ResetWatch()
    ScrollTop()
    Layout()
end

-- The level picker next to each database source: every level with the vault's item level for
-- it. Levels the game hasn't given an item level for can't be picked, so none is ever guessed.
local function OpenLevelMenu(anchor, sourceID)
    local levels = BGV.Rewards and type(BGV.Rewards.DatabaseLevels) == "function" and BGV.Rewards.DatabaseLevels(sourceID) or {}
    local function Pick(level)
        db.levels[sourceID] = level
        ResetWatch()
        ScrollTop()
        Layout()
    end
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        -- No menu API: step to the next level with a known item level.
        local current = DatabaseLevel(sourceID)
        local start = 0
        for index, info in ipairs(levels) do
            if info == current then
                start = index
            end
        end
        for offset = 1, #levels do
            local info = levels[(start + offset - 1) % #levels + 1]
            if info.itemLevel then
                Pick(info.level)
                return
            end
        end
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        root:CreateTitle(L["Vault reward item level"])
        local lastFrom
        for _, info in ipairs(levels) do
            local level = info.level
            local itemLevel = ItemLevelText(info)
            if info.from and info.from ~= lastFrom then
                lastFrom = info.from
                root:CreateTitle(L[TIER_FROM_TITLES[info.from] or info.from])
            end
            local text = (info.menuLabel or info.label) .. "  |cff8a8a8e" .. (itemLevel or L["unknown"]) .. "|r"
            local radio = root:CreateRadio(text, function()
                return db.levels[sourceID] == level
            end, function()
                Pick(level)
            end)
            if not itemLevel and radio and type(radio.SetEnabled) == "function" then
                radio:SetEnabled(false)
            end
        end
    end)
end

-- Class (or all classes), then spec or all specs, laid out like the Adventure Guide's loot filter.
local function OpenClassMenu(anchor)
    if not (MenuUtil and type(MenuUtil.CreateContextMenu) == "function") then
        -- No menu API: step through the class's specs and "All specs".
        local specs = BGV.Utils.ClassSpecs(db.classID)
        local nextSpec = specs[1] and specs[1].id or 0
        for index, spec in ipairs(specs) do
            if spec.id == db.specID then
                nextSpec = specs[index + 1] and specs[index + 1].id or 0
            end
        end
        SetDatabaseClass(db.classID, nextSpec)
        return
    end
    MenuUtil.CreateContextMenu(anchor, function(_, root)
        local classMenu = root:CreateButton(BGV.Utils.GameText("CLASS", "Class"))
        classMenu:CreateRadio(AllClassesText(), function()
            return db.classID == 0
        end, function()
            SetDatabaseClass(0, 0)
        end)
        for _, class in ipairs(BGV.Utils.Classes()) do
            local classID = class.id
            classMenu:CreateRadio(BGV.Utils.ClassColorText(class.file, class.name), function()
                return db.classID == classID
            end, function()
                SetDatabaseClass(classID, 0)
            end)
        end
        -- Specs only for a chosen class; with all classes there's nothing to narrow down.
        local class = ClassInfo(db.classID)
        if not class then
            return
        end
        root:CreateTitle(BGV.Utils.ClassColorText(class.file, class.name))
        for _, spec in ipairs(BGV.Utils.ClassSpecs(db.classID)) do
            local specID = spec.id
            root:CreateRadio(spec.name, function()
                return db.specID == specID
            end, function()
                SetDatabaseClass(db.classID, specID)
            end)
        end
        root:CreateRadio(L["All specs"], function()
            return (db.specID or 0) == 0
        end, function()
            SetDatabaseClass(db.classID, 0)
        end)
    end)
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
    frame = CreateFrame("Frame", "BetterGreatVaultLootTable", UIParent)
    frame:SetSize(1000, 560)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(840, 400, 1400, 900)
    end
    frame:Hide()
    -- Flat, like the settings panel: a soft shadow, a dark body with a 1px border, and a title
    -- bar with a thin gold rule.
    for step, alpha in ipairs({ 0.22, 0.14, 0.07 }) do
        local shadow = Pixel(frame, "BACKGROUND", 0, 0, 0, alpha)
        shadow:SetDrawLayer("BACKGROUND", -8)
        shadow:SetPoint("TOPLEFT", -2 * step, 2 * step)
        shadow:SetPoint("BOTTOMRIGHT", 2 * step, -2 * step)
    end
    local body = Pixel(frame, "BACKGROUND", 0.055, 0.055, 0.065, 0.97)
    body:SetDrawLayer("BACKGROUND", -7)
    body:SetAllPoints()
    BGV.Utils.Border(frame, 0.24, 0.24, 0.27, 1)

    local titleBar = Pixel(frame, "BACKGROUND", 0.085, 0.085, 0.097, 1)
    titleBar:SetPoint("TOPLEFT", 1, -1)
    titleBar:SetPoint("TOPRIGHT", -1, -1)
    titleBar:SetHeight(39)
    local titleRule = Accent(Pixel(frame, "ARTWORK", 1, 1, 1, 1), 0.6)
    titleRule:SetHeight(1)
    titleRule:SetPoint("TOPLEFT", titleBar, "BOTTOMLEFT", 0, 0)
    titleRule:SetPoint("TOPRIGHT", titleBar, "BOTTOMRIGHT", 0, 0)

    local title = BGV.Utils.FontString(frame, "OVERLAY", "Normal")
    title:SetPoint("TOPLEFT", 16, -14)
    title:SetText(L["Great Vault loot"])
    title:SetTextColor(0.85, 0.65, 0.2)
    windowTitle = title

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

    -- A flat close button: two thin crossed lines, red glow on hover.
    local close = CreateFrame("Button", nil, frame)
    close:SetSize(26, 26)
    close:SetPoint("TOPRIGHT", -7, -7)
    local closeGlow = Pixel(close, "HIGHLIGHT", 0.85, 0.2, 0.2, 0.35)
    closeGlow:SetAllPoints()
    local cross = {}
    for index, angle in ipairs({ 45, -45 }) do
        local line = Pixel(close, "ARTWORK", 0.62, 0.62, 0.65, 1)
        line:SetSize(14, 2)
        line:SetPoint("CENTER", close, "CENTER", 0, 0)
        if line.SetRotation then
            line:SetRotation(math.rad(angle))
        end
        cross[index] = line
    end
    close:SetScript("OnEnter", function()
        for _, line in ipairs(cross) do
            line:SetVertexColor(1, 1, 1, 1)
        end
    end)
    close:SetScript("OnLeave", function()
        for _, line in ipairs(cross) do
            line:SetVertexColor(0.62, 0.62, 0.65, 1)
        end
    end)
    close:SetScript("OnClick", function()
        frame:Hide()
    end)

    specButton = BGV.Utils.CreateLootSpecButton(frame, true)
    specButton:SetPoint("TOPRIGHT", -42, -9)

    -- Database mode: the class and spec to list loot for, in the loot spec button's place.
    classButton = BGV.Utils.CreateFlatButton(frame, 200, 22)
    classButton:SetPoint("TOPRIGHT", -42, -9)
    classButton:SetScript("OnClick", function(self)
        OpenClassMenu(self)
    end)
    classButton:Hide()

    -- The drag strip spans most of the title bar; keep the header buttons above it so
    -- clicks reach them instead of starting a window drag.
    specButton:SetFrameLevel(drag:GetFrameLevel() + 2)
    classButton:SetFrameLevel(drag:GetFrameLevel() + 2)

    rail = CreateFrame("Frame", nil, frame)
    rail:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -40)
    rail:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    rail:SetWidth(LEFT_W)
    local railBack = Pixel(rail, "BACKGROUND", 0.035, 0.035, 0.042, 0.8)
    railBack:SetPoint("TOPLEFT", rail, "TOPLEFT", 1, 0)
    railBack:SetPoint("BOTTOMRIGHT", rail, "BOTTOMRIGHT", 0, 1)
    local contents = BGV.Utils.FontString(rail, "OVERLAY", "Normal")
    contents:SetPoint("TOPLEFT", rail, "TOPLEFT", 16, -12)
    contents:SetText(L["Contents"])
    contents:SetTextColor(0.85, 0.65, 0.2)
    railTitle = contents

    -- Database mode's sources, each with its level picker (difficulty, keystone level or tier).
    for _, source in ipairs(DB_SOURCES) do
        local row = CreateFrame("Button", nil, rail)
        row:SetHeight(54)
        row.hover = Pixel(row, "HIGHLIGHT", 1, 1, 1, 0.05)
        row.hover:SetAllPoints()
        row.bar = Accent(Pixel(row, "ARTWORK", 1, 1, 1, 1))
        row.bar:SetSize(2, 40)
        row.bar:SetPoint("LEFT", row, "LEFT", 0, 0)
        row.bar:Hide()
        -- A checkbox like the settings panel's: sources can be listed together.
        row.box = Pixel(row, "BACKGROUND", 0.16, 0.16, 0.17, 1)
        row.box:SetSize(12, 12)
        row.box:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -8)
        BGV.Utils.Border(row, 0.36, 0.36, 0.4, 1, row.box)
        row.fill = Accent(Pixel(row, "ARTWORK", 1, 1, 1, 1))
        row.fill:SetSize(6, 6)
        row.fill:SetPoint("CENTER", row.box, "CENTER", 0, 0)
        row.fill:Hide()
        row.label = BGV.Utils.FontString(row, "OVERLAY", "Highlight")
        row.label:SetPoint("TOPLEFT", row, "TOPLEFT", 30, -6)
        row.label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        row.label:SetJustifyH("LEFT")
        row.label:SetWordWrap(false)
        row.level = BGV.Utils.CreateFlatButton(row, 120, 20)
        row.level:SetPoint("TOPLEFT", row, "TOPLEFT", 12, -26)
        row.level:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        local sourceID = source.id
        row:SetScript("OnClick", function()
            ToggleDatabaseSource(sourceID)
        end)
        row.level:SetScript("OnClick", function(self)
            OpenLevelMenu(self, sourceID)
        end)
        row:Hide()
        dbRows[sourceID] = row
    end
    local divider = Pixel(frame, "BORDER", 0.18, 0.18, 0.2, 1)
    divider:SetWidth(1)
    divider:SetPoint("TOPLEFT", rail, "TOPRIGHT", 0, 0)
    divider:SetPoint("BOTTOMLEFT", rail, "BOTTOMRIGHT", 0, 1)
    rail.divider = divider

    headerTitle = BGV.Utils.FontString(frame, "OVERLAY", "NormalLarge")
    headerTitle:SetPoint("TOPLEFT", frame, "TOPLEFT", LEFT_W + 20, -46)
    headerTitle:SetJustifyH("LEFT")
    headerTitle:SetWordWrap(false)
    headerTitle:SetTextColor(0.96, 0.96, 0.96)
    headerReward = BGV.Utils.FontString(frame, "OVERLAY", "Highlight")
    headerReward:SetPoint("TOPLEFT", headerTitle, "BOTTOMLEFT", 0, -4)
    headerReward:SetJustifyH("LEFT")
    headerReward:SetWordWrap(false)
    headerReward:SetTextColor(1, 0.82, 0)
    local rule = Accent(Pixel(frame, "ARTWORK", 1, 1, 1, 1), 0.9)
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
    Pixel(columnHeader, "BACKGROUND", 0.1, 0.1, 0.112, 1):SetAllPoints()
    local headerRule = Accent(Pixel(columnHeader, "ARTWORK", 1, 1, 1, 1), 0.45)
    headerRule:SetHeight(1)
    headerRule:SetPoint("BOTTOMLEFT")
    headerRule:SetPoint("BOTTOMRIGHT")
    columnHeader.labels = {}
    for _, column in ipairs({ { "item", "Item" }, { "tier", "Tier" }, { "level", "Item Level" }, { "stats", "Secondary stats" }, { "slot", "Slot" } }) do
        local label = BGV.Utils.FontString(columnHeader, "OVERLAY", "NormalSmall")
        label:SetText(BGV.Utils.Upper(L[column[2]]))
        label:SetTextColor(0.66, 0.66, 0.7)
        label:SetJustifyH("LEFT")
        label:SetWordWrap(false)
        columnHeader.labels[column[1]] = label
        -- A label cut short to fit its column (PlaceHeader) shows its full name on hover.
        local hover = CreateFrame("Frame", nil, columnHeader)
        hover:SetAllPoints(label)
        hover:EnableMouse(true)
        hover:SetScript("OnEnter", function(self)
            if GameTooltip and label:IsShown() and label:IsTruncated() then
                GameTooltip:SetOwner(self, "ANCHOR_TOP")
                GameTooltip:SetText(L[column[2]])
                GameTooltip:Show()
            end
        end)
        hover:SetScript("OnLeave", function()
            if GameTooltip then
                GameTooltip:Hide()
            end
        end)
        label.hover = hover
    end
    -- The gear and secondary stat filters, as small buttons after their columns' labels.
    statFilterButton = CreateHeaderFilter(columnHeader.labels.stats, function(self)
        OpenStatMenu(self)
    end, function(tooltip)
        tooltip:SetText(L["Secondary stats filter"])
        tooltip:AddLine(StatFilterSummary(), 1, 1, 1)
        tooltip:AddLine(L["Pick one stat for items with it, two for items with both, three or more for items with any of them."], 0.7, 0.7, 0.72, true)
    end)
    gearFilterButton = CreateHeaderFilter(columnHeader.labels.slot, function(self)
        OpenGearMenu(self)
    end, function(tooltip)
        tooltip:SetText(L["Gear filter"])
        tooltip:AddLine(filterID == "ALL" and L["Showing all gear"] or string.format(L["Showing: %s"], GearFilterLabel()), 1, 1, 1)
    end)
    searchBox = CreateSearchBox(columnHeader.labels.item)
    RefreshHeaderFilters()
    child = CreateFrame("Frame", nil, scroll)
    child:SetSize(520, 40)
    scroll:SetScrollChild(child)
    -- A thin scroll indicator in the right margin, shown only when the list overflows.
    local track = Pixel(frame, "ARTWORK", 1, 1, 1, 0.05)
    track:SetWidth(3)
    track:SetPoint("TOPLEFT", scroll, "TOPRIGHT", 6, 0)
    track:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", 6, 0)
    local thumb = Accent(Pixel(frame, "OVERLAY", 1, 1, 1, 1), 0.7)
    thumb:SetWidth(3)
    UpdateScrollThumb = function()
        local range = scroll:GetVerticalScrollRange() or 0
        local height = scroll:GetHeight() or 0
        if range <= 0 or height <= 0 then
            track:Hide()
            thumb:Hide()
            return
        end
        local thumbHeight = math.max(24, height * height / (height + range))
        local offset = (scroll:GetVerticalScroll() or 0) / range * (height - thumbHeight)
        thumb:SetHeight(thumbHeight)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -offset)
        track:Show()
        thumb:Show()
    end
    scroll:SetScript("OnScrollRangeChanged", function()
        UpdateScrollThumb()
    end)
    scroll:SetScript("OnVerticalScroll", function()
        UpdateScrollThumb()
        PaintVisible()
    end)
    scroll:SetScript("OnSizeChanged", function()
        PaintVisible()
    end)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = self:GetVerticalScrollRange() or 0
        local target = (scrollTarget or self:GetVerticalScroll()) - delta * 64
        scrollTarget = math.max(0, math.min(maxScroll, target))
    end)
    scroll:SetScript("OnUpdate", function(self, elapsed)
        if not scrollTarget then
            return
        end
        local current = self:GetVerticalScroll()
        local distance = scrollTarget - current
        if math.abs(distance) < 0.5 then
            self:SetVerticalScroll(scrollTarget)
            scrollTarget = nil
        else
            self:SetVerticalScroll(current + distance * math.min(1, elapsed * 14))
        end
        if tipWaiting and not ListMoving() then
            ShowTipUnderPointer()
        end
    end)

    local sizer = CreateFrame("Button", nil, frame)
    sizer:SetSize(14, 14)
    sizer:SetPoint("BOTTOMRIGHT", -3, 3)
    sizer:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    sizer:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    sizer:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
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
    -- The database's reads are only kept while it's open.
    frame:HookScript("OnHide", function()
        if mode == "database" then
            itemCache = {}
            if BGV.Rewards and type(BGV.Rewards.ClearDatabase) == "function" then
                BGV.Rewards.ClearDatabase()
            end
        end
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

    -- Escape closes the window through the game's list of windows to close, with the others.
    -- Never replace or wrap the game's CloseWindows to close it first (an earlier version did):
    -- the game closes windows that way on Escape, on death and on loading screens, and with the
    -- addon's function in the chain, everything it closed was tainted. The Group Finder then
    -- failed on protected values ("execution tainted by BetterGreatVault").
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

-- Shows the window laid out once: showing it lays it out (OnShow), so only one already open
-- needs a new layout.
local function ShowLaidOut(window)
    if window:IsShown() then
        Layout()
    else
        window:Show()
    end
    window:Raise()
end

function BGV.LootTable.Show(slot)
    local window = Build()
    if mode == "database" and BGV.Rewards and type(BGV.Rewards.ClearDatabase) == "function" then
        BGV.Rewards.ClearDatabase()
    end
    mode = "vault"
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
    JumpScroll(0)
    ShowLaidOut(window)
end

-- Repaints an open table (the accent color changed in the settings).
function BGV.LootTable.RefreshStyle()
    if frame and frame:IsShown() then
        Layout()
    end
end

function BGV.LootTable.ShowSlot(slot)
    if type(slot) ~= "table" or not slot.unlocked then
        return
    end
    BGV.LootTable.Show(slot)
end

function BGV.LootTable.Toggle()
    local window = Build()
    if window:IsShown() and mode == "vault" and not solo then
        window:Hide()
        return
    end
    BGV.LootTable.Show(nil)
end

function BGV.LootTable.ShowDatabase()
    local window = Build()
    mode = "database"
    solo = false
    itemCache = {}
    templateCache = {}
    ResetWatch()
    if not BGV.Utils.IsUsableNumber(db.classID) then
        db.classID = BGV.Utils.PlayerClassID()
        db.specID = BGV.Utils.LootSpecID() or 0
    end
    PlaceHeaders()
    ScrollTop()
    ShowLaidOut(window)
end

function BGV.LootTable.ToggleDatabase()
    local window = Build()
    if window:IsShown() and mode == "database" then
        window:Hide()
        return
    end
    BGV.LootTable.ShowDatabase()
end
