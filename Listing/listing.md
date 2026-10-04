# Better Great Vault on CurseForge and Wago

What to fill in when creating the project on each site. The description is the same Markdown on
both: [description.md](description.md). Nothing in this folder ships with the addon.

## The fields

| Field | Value |
| --- | --- |
| Name | Better Great Vault |
| URL slug (CurseForge) | `better-great-vault` |
| Summary (152 characters) | Exact item levels and loot previews on every Great Vault slot, a loot table and season loot database, and an opening animation for every specialization. |
| Short summary, if a field is shorter (102 characters) | Exact item levels, loot reels and a loot database for the Great Vault, with an opening for every spec. |
| Description | [description.md](description.md), as Markdown |
| Logo | [logo.png](logo.png) (1024 x 1024; CurseForge asks for a 400 x 400 PNG and scales larger ones down). A GIF logo isn't in either site's rules: submit the PNG, keep the GIF for the description |
| License | All Rights Reserved |
| Game | World of Warcraft, Retail only (12.1.0 and 12.1.5, Midnight) |
| Main category (CurseForge) | Miscellaneous |
| More categories (CurseForge) | Boss Encounters (raid and dungeon loot), Tooltip, Map & Minimap |
| Categories (Wago) | The same ones, or the closest Wago offers |
| Source code link | `https://github.com/powercover/BetterGreatVault`, only once the repository is public |
| Issues link | `https://github.com/powercover/BetterGreatVault/issues`, only once the repository is public |
| Donation link | none (your call; keep it out of the addon itself) |

## The repository is private

GitHub answers 404 to anyone else, so before publishing decide one way or the other:

- **Make it public.** The license stays All Rights Reserved: people can read the code, not reuse
  it. Then the issue link, the source link and GitHub releases all work for players.
- **Keep it private.** Leave the source and issue links empty, and change the last line of
  description.md to ask for feedback in the page's comments instead. GitHub releases would then
  only be for you.

## Images

Upload these to each project's image gallery, then put each one's address in description.md in
place of its placeholder. All of them are 2560 x 1440 except the emblem.

| Placeholder | Image |
| --- | --- |
| `IMAGE_EMBLEM` | [emblem.gif](emblem.gif): the settings page's spinning emblem, one 6.2 s loop. [emblem.webp](emblem.webp) is the same loop in full color at half the size, but not for CurseForge: its moderation page warns of a bug with WebP images |
| `IMAGE_COMPARE` | [compare.png](compare.png): Blizzard's vault next to the same vault with the addon, and the same slot of each up close |
| `IMAGE_REVEAL` | [reveal.png](reveal.png): reward day |
| `IMAGE_OPENINGS` | [openings.png](openings.png): all 43 opening styles at their signature moment, by class and specialization |
| `IMAGE_LOOT_TABLE` | [loot-table.png](loot-table.png): the loot table |
| `IMAGE_DATABASE` | [database.png](database.png): the loot database |
| `IMAGE_MINIMAP` | [minimap.png](minimap.png): the minimap button's popup |

The gallery's own order, best first: compare, openings, reveal, loot table, database, minimap.

`openings.png` is drawn by the addon's own animation code with its own effect art; Blizzard's card
(the gates' face) and the loot icons in it are stand-ins drawn to look like the game's. The other
cards are in-game screenshots ([shots/](shots/)), framed.

### Retaking the screenshots

For a new season or a changed feature. For all of them: the game's default UI scale, a plain spot
(no nameplates or chat over the vault), other addons' frames out of the way. The game saves JPG at
quality 3 of 10 by default, which smears the UI's text: run `/console screenshotQuality 10` once,
or `/console screenshotFormat tga` for lossless shots.

1. **Blizzard's vault** (`vault-blizzard`). Turn Better Great Vault off in the AddOns list,
   `/reload`, open the Great Vault, and take the shot with the mouse away from the slots.
2. **The same vault with the addon** (`vault-addon`). Turn it back on, `/reload`, open the vault
   the same way, and point at an unlocked slot so its loot reel shows. Same week as shot 1.
3. **Reward day, before you choose** (`reward-day`). At the vault, once every slot has landed on
   its reward.
4. **The loot table** (`loot-table`). Left-click an unlocked slot.
5. **The loot database** (`loot-database`). Shift + middle-click the minimap button.
6. **The minimap popup** (`minimap-popup`). Point at the minimap button.

## CurseForge

1. On authors.curseforge.com, create a project: World of Warcraft, Addons.
2. Fill in the fields above and upload the logo; paste description.md into the description, in
   the editor's Markdown mode if it offers one.
3. Upload the first file: the addon's zip, which then goes to the moderators for review. The
   project ID is shown on the project page once it exists.

## Wago

1. On addons.wago.io, open the developer dashboard and create an addon.
2. Fill in the fields above, upload the logo and screenshots, and paste description.md.
3. The project ID is the 8-character code under the addon's name on the dashboard.

Both IDs go into the TOC (`## X-Curse-Project-ID` and `## X-Wago-ID`) for automatic releases.

## The art

`logo.png`, `logo-transparent.png`, `emblem.gif` and `emblem.webp` are the addon's own emblem,
drawn at full size from the same art as its textures; the animation replays the settings page's
spin frame by frame.
