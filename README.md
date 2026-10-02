# Better Great Vault

**See what your Great Vault can give before you choose.**

Better Great Vault shows every slot's possible loot at the exact item level it would award,
tracks your progress toward the next slot, and lets you browse every reward the vault can give
this season, for any class, so you can plan what to run next.

![Game version](https://img.shields.io/badge/WoW-Retail%2012.1%20(Midnight)-1f6fb2)
![Addon version](https://img.shields.io/badge/version-1.0.0-d9a633)
![Dependencies](https://img.shields.io/badge/dependencies-none-3c9a5f)

## Features

### On the Great Vault

- **Progress and reward on every slot.** Each slot shows how far along it is (`3 / 4 Raid Bosses`)
  and, once unlocked, the reward's upgrade track and exact item level.
- **Loot reels.** Hovering an unlocked slot opens its gates and spins a reel of every item that
  slot can give you.
- **Opening styles.** How a slot opens: Vault Door (heavy doors that unlatch and slide apart),
  Classic, One-Armed Bandit (a slot machine whose reels stop on the payline), Arcane Portal, Frost
  Shatter, Fel Fire and Old Cartoon. By default the style matches your specialization (Frost
  Shatter for frost mages and frost death knights, Fel Fire for demon hunters and warlocks, Arcane
  Portal for arcane mages and Devourer demon hunters, One-Armed Bandit for outlaw rogues, Old
  Cartoon for brewmasters, Vault Door for everyone else); you can also pick one, or a random one
  each time.
- **Detailed tooltips.** A slot's tooltip lists what counts toward it (bosses killed, Mythic+ runs,
  world activity tiers), what the next slot needs, and the next step up in reward.
- **Best-in-Slot tiers.** Reel items are colored by their Best-in-Slot tier for your loot
  specialization (S, A, B, C, D), taken from Wowhead's class guides. Catalyzed items keep their
  stats this season, so where a guide catalyzes a raid or Mythic+ piece into your class set, that
  piece is S and the set piece as it drops is A.
- **Loot spec button.** See and change the specialization your vault loot is filtered by, right on
  the vault.
- **Claim week stays Blizzard's.** While rewards are waiting to be claimed, the addon leaves the
  Great Vault exactly as Blizzard made it, so choosing your reward works as usual.

### Loot table

Left-click an unlocked slot, or middle-click the minimap button, to list every reward it can give:

- your class set (tier) pieces first: any slot can award them, raid, Mythic+ or world, whichever
  bosses you killed. Their tooltips, and the set's header, show the set's bonuses for your loot
  specialization (the Great Vault's loot spec button);
- then grouped by raid boss or dungeon, with each item at the exact item level the slot awards;
- columns for Best-in-Slot tier, item level, secondary stats, and slot with armor type;
- a search box for item names, and filters for gear slot and secondary stats (one stat: items
  with it; two: items with both; three or more: items with any of them);
- item tooltips at that item level, compared with your gear while you hold Shift (or always, with
  the game's **Always compare items** option), as in the Great Vault;
- a resizable window that follows your accent color.

### Loot database

Everything the Great Vault can award this season, as if all content were done, for any class and
specialization or all of them at once. Pick your sources and their levels:

| Source | Covers | Level |
| --- | --- | --- |
| Tier set | Your class's set pieces (or every class's), which any vault slot can award | Any raid difficulty, keystone level or world tier |
| Raid | Every boss of the season's raids, killed or not | Difficulty |
| Mythic+ keystones | Every dungeon of the season | Keystone level |
| World | Delve, prey and world boss gear | Tier |

The tier set, Raid and Mythic+ are listed to start with, and sources can be listed together. A
level whose exact item level isn't known can't be picked: the database never guesses. The tier
set's pieces and header show the set's bonuses for the chosen specialization, or for each of the
class's specializations with All specs or All classes.

### Minimap button and addon compartment

- An animated vault door: the handle turns on hover, and the gem pulses while rewards are waiting.
- Hover it for this week's vault at a glance: each slot's item level or progress, the time until the
  weekly reset, and what each click does.
- Listed in the minimap's addon compartment too (Blizzard's addon menu, the minimap button with a
  number), with the same clicks.
- A data broker feed for data bars such as ElvUI's, Titan Panel or ChocolateBar: this week's
  unlocked slots (`5/9`), with the same clicks and popup. It appears when another addon has loaded
  LibDataBroker; nothing is bundled for it.
- Options to lock or reset its position, fade it out until hovered, and keep it on the minimap when
  another addon gathers minimap buttons.

### And more

- A reminder in chat at login when rewards are waiting, and `/bgv status` for this week's vault in chat.
- Text size from -5 to +5 for all of the addon's text.
- Eleven languages, including Ukrainian (see [Languages](#languages)).
- An accent color: your specialization's color, or one you pick.
- Key bindings, with none bound by default.
- Settings saved per character.

## Installation

### CurseForge and Wago

Coming soon.

### Manual

1. Download the latest version from GitHub (**Code → Download ZIP**).
2. Extract it into `World of Warcraft/_retail_/Interface/AddOns/`.
3. Rename the folder to `BetterGreatVault` (GitHub names it `BetterGreatVault-main`). The `.toc`
   file must sit directly inside it: `Interface/AddOns/BetterGreatVault/BetterGreatVault.toc`.
4. Restart the game and make sure **Better Great Vault** is enabled in the AddOns list.

No other addons are required.

## Usage

### Minimap button

| Click | Action |
| --- | --- |
| Left-click | Open or close the Great Vault |
| Middle-click | Loot table for your unlocked slots |
| Shift + middle-click | Loot database |
| Right-click | Settings |
| Drag | Move the button around the minimap |

The entry in the minimap's addon compartment takes the same clicks.

### Chat commands

| Command | Action |
| --- | --- |
| `/bgv` | Version and the list of commands |
| `/bgv status` | This week's Great Vault in chat: each slot's item level or progress |
| `/bgv db` | Open or close the loot database |
| `/bgv debug` | Turn debug mode on or off; turning it on prints the vault's slots |
| `/bgv refresh` | Read the Great Vault again |
| `/bgv perf` | What the addon costs: CPU time a frame and slow frames (from the game's addon profiler, counted since the game started), memory, how long it took to load, and the last slot animation and loot table load |
| `/bgv reset` | Reset settings, keeping what the addon learned about this season's rewards |

### Key bindings

In the game's **Key Bindings**, the **Better Great Vault** section has bindings for the Great Vault,
the loot table, the loot database and the settings. No keys are bound until you choose them.

## Settings

Right-click the minimap button, or open the game's **Options → AddOns → Better Great Vault**.

| Section | Options |
| --- | --- |
| Great Vault | Animated slots (with the opening style: your specialization's, one you pick, or random), Best-in-Slot tiers, open the loot table from a slot, loot spec button, reward reminder |
| Minimap button | Addon compartment entry; show the button, with reset position, popup on mouseover (and its week's slots), lock position, unaffected by other addons, and fade out when not hovered |
| Appearance | Text size, language, accent color |
| Key bindings | The current keys, and a shortcut to the game's Key Bindings |
| Tools | Open the Great Vault, loot table or loot database; debug mode; print or refresh vault data; print performance; reset settings; chat commands |
| About | Version, author and links |

## Languages

English, Deutsch, Español (Spain and Latin America), Français, Italiano, Português, Русский,
Українська, 한국어, 简体中文 and 繁體中文.

The addon speaks the game's language unless you pick another under **Settings → Appearance →
Language**; the game has no Ukrainian version, so that's where Ukrainian is chosen. A new language
shows after the interface reloads. Names that only the game knows, such as items, bosses, dungeons,
classes and specializations, stay in the game's language.

Translations live in `Locales/`, one file per language, each line pairing the English text with its
translation. Corrections are welcome.

## How item levels are worked out

Item levels come from the game's own reward data. When the game can't confirm one, the addon shows
it as unknown rather than guessing.

- **Unlocked slots** use the vault's generated reward, or Blizzard's example reward for the slot.
  Locked slots show no item level: the reward isn't final until the slot unlocks.
- **Raid slots** follow the vault's actual rule. On Mythic, only loot from a raid's last two bosses
  can reach the top item level, and only once one of them has been killed on Mythic. Blizzard's
  example reward shows the top level either way; the addon corrects it using this season's Mythic
  item levels.
- **Reels and the loot table** show each item at the exact item level the slot awards.
- **The loot database** reads the vault's upgrade steps for this season from the game, and adds what
  your own vault has shown this season.

Raid and dungeon loot comes from the Encounter Journal, and world gear from the addon's list of
this season's items. The addon reads the journal without disturbing the Adventure Guide: whatever
the guide was showing is put back after each read.

## Compatibility

- Retail World of Warcraft 12.1.0 and 12.1.5 (`Interface: 120100, 120105`). The addon doesn't load
  on Classic.
- Works with addons that gather minimap buttons into a bar or menu, such as EllesmereUI. To keep the
  button on the minimap instead, turn on **Unaffected by other addons**.

## Known limitations

- Best-in-Slot tiers come from Wowhead's guides as of this version, and can lag behind guide
  updates.
- In the loot database, Raid Finder, Normal and Heroic item levels are learned from your own vault.
  Until your vault has shown one, that difficulty can't be picked.
- In a new season, loot database levels appear once the game reports them or your vault has shown
  them.
- The game doesn't name individual delves or world activities for the vault, so the tooltip lists
  tiers and counts.
- Right after login, an item level can be missing for a moment while the game loads item data.

## Reporting issues

Open an issue at [github.com/powercover/BetterGreatVault/issues](https://github.com/powercover/BetterGreatVault/issues)
and include:

- your game version (`/dump GetBuildInfo()`);
- the output of **Tools → Print vault data**, or `/bgv debug`;
- whether the slot was locked, unlocked, or ready to claim;
- for slowdowns, the output of `/bgv perf` right after they happen;
- a screenshot, if the problem is visual.

## Development

The addon is plain Lua with no libraries.

| File | Purpose |
| --- | --- |
| `Core.lua` | Events, saved settings, chat commands, key bindings, the login reminder |
| `GreatVault.lua` | Reads the vault's slots, progress and rewards |
| `Rewards.lua` | Loot lists and item levels from the Encounter Journal; the loot database |
| `UI.lua` | The Great Vault overlay: each slot's text and hover, and the slot art it replaces |
| `Case.lua` | What an unlocked slot shows when hovered: its gates, the loot reel and the opening styles |
| `Tooltip.lua` | The slot tooltip |
| `LootTable.lua` | The loot table and loot database window |
| `Minimap.lua` | The minimap button, its popup, and the addon compartment entry |
| `Settings.lua` | The options page |
| `Utils.lua` | Shared helpers, fonts, accent colors and flat widgets |
| `Bis.lua` | Best-in-Slot tiers per specialization |
| `WorldLoot.lua` | The season's world gear: delves, prey and world bosses |
| `Locales/` | Translations: the language system and one file per language |
| `Bindings.xml` | Key bindings |
| `Media/` | The icon's layers (minimap button, emblem) and the opening styles' art |

### Tests

The tests run the addon's Lua against a model of the game's APIs. They need Python 3 and
[lupa](https://pypi.org/project/lupa/) (`pip install lupa`).

```sh
cd tests
python run.py        # loot list refresh checks
python scenarios.py  # item level and loot scenarios
```

## Author

Made by **powercover**. Best-in-Slot tiers are based on Wowhead's class guides.
