# Better Great Vault

Author: powercover  
Version: 1.0.0

Better Great Vault adds a short progress and reward summary to each slot in Blizzard's Great Vault, plus a detailed mouseover section on the normal game tooltip.

The default Great Vault window is left in place. The addon only anchors text to the existing slot frames and appends tooltip lines after Blizzard's own tooltip.

## Supported versions

Retail WoW 12.1.0 and 12.1.5 (`Interface: 120100, 120105`).

The addon is marked `mainline` only. It does not load on Classic.

## Installation

1. Copy the `BetterGreatVault` folder into:

   `World of Warcraft/_retail_/Interface/AddOns/`

2. The folder must contain `BetterGreatVault.toc` directly inside it:

   `Interface/AddOns/BetterGreatVault/BetterGreatVault.toc`

3. Restart WoW, or reload the UI with `/reload`.
4. Enable **Better Great Vault** on the AddOns list.

No other addons are required.

## Features

- Compact progress on every Raid, Dungeon, World, and PvP Great Vault slot that Blizzard's UI actually shows.
- Reward item level when Blizzard returns an example reward or a generated vault item.
- Mouseover detail for the activities that count toward that slot.
- Data, thresholds, and item levels come from `C_WeeklyRewards` and related Retail APIs. Season thresholds are not hardcoded.

## Slash commands

| Command | Action |
| --- | --- |
| `/bgv` | Show version and command help. |
| `/bgv debug` | Toggle debug mode. When enabled, print the current vault snapshot once. |
| `/bgv refresh` | Refresh the open Great Vault display. |
| `/bgv reset` | Clear saved settings (debug mode). |

## Debug mode

`/bgv debug` turns debug on or off. Turning it on prints one snapshot, for example:

```
Category: Dungeons | Slot: 1 | Progress: 4 | Required: 1 | Reward ilvl: 246
```

Debug does not print on a timer and does not print every time the vault updates. Run `/bgv debug` again when you want a new snapshot. If a protected call fails, the same command also prints the last stored error.

## How reward item level is determined

For each slot returned by `C_WeeklyRewards.GetActivities()`:

1. If the weekly reward has already been generated, the addon uses `C_WeeklyRewards.GetItemHyperlink(itemDBID)` on the non-keystone item rewards and reads `C_Item.GetDetailedItemLevelInfo`.
2. Otherwise, once `progress >= threshold`, it uses `C_WeeklyRewards.GetExampleRewardItemHyperlinks(activity.id)` and reads the item level from that example link. This is the same preview Blizzard shows on an unlocked slot.
3. If the item is not cached yet, the addon waits for `Item:ContinueOnLoad` and fills in the line when the client returns a level.
4. Locked slots do not get an item level. The reward is not final until the threshold is met.
5. `C_WeeklyRewards.GetNextActivitiesIncrease` is used only for the tooltip's higher-reward section. Its item level is the next breakpoint, not the current slot.

There is no key-level to item-level table in this addon.

## How progress is determined

- Slot progress, threshold, level, and category come from `C_WeeklyRewards.GetActivities()`.
- Mythic+ rows come from `C_MythicPlus.GetRunHistory` for the current week and season. The top runs up to that slot's threshold are marked as counting. The run at the threshold position is marked as the one that sets the reward. Heroic or Mythic dungeon counts from `C_WeeklyRewards.GetNumCompletedDungeonRuns` fill any remaining spots, without inventing dungeon names.
- Raid bosses come from `C_WeeklyRewards.GetActivityEncounterInfo`. Names come from the Encounter Journal. Defeated bosses are ordered by difficulty, and the top kills up to the slot threshold are marked as counting.
- World rows come from `C_WeeklyRewards.GetSortedProgressForActivity`. The API exposes tier and completion counts, not individual delve names.

## Known API limitations

- Individual Delve or world-activity names are not provided. The tooltip lists tier counts only.
- Individual PvP matches are not provided. PvP slots show progress, tier name, and item level when the API has them. Blizzard shows either the World row or the PvP row.
- Locked slots have no reliable reward item level. The addon leaves that line off instead of guessing.
- Example reward links can be briefly unavailable until item data loads.
- Encounter names depend on the Encounter Journal. If a name is unavailable, the encounter id is shown.
- Mythic+ map names depend on challenge-mode map info. An unknown map is shown as `Mythic+ <id>`.
- Failed keys are not listed. `GetRunHistory` is asked for completed runs only.
- Concession and "also receive" rewards are not vault slots and are not annotated.
- The addon does not replace Blizzard's tooltip. It adds a Great Vault section after the default text.

## Reporting compatibility issues

Include:

- WoW version and build (`/dump GetBuildInfo()`).
- `/bgv debug` output.
- Whether the slot was locked, unlocked, or ready to claim.
- A screenshot of the Great Vault slot and tooltip.

API changes to watch:

- `Enum.WeeklyRewardChestThresholdType`
- `WeeklyRewardsFrame:GetActivityFrame`
- `WeeklyRewardsActivityMixin:Refresh`, `OnEnter`, and `ShowPreviewItemTooltip`
- `C_WeeklyRewards.GetActivities` and `GetExampleRewardItemHyperlinks`

Internal frame references are isolated in `UI.lua` and `Tooltip.lua`.
