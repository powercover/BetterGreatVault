# Test kit

Offline checks for the addon, on WoW's own Lua (5.1, through lupa). Nothing here ships: `.pkgmeta`
leaves `tests/` out of the release zip.

```
pip install lupa
python suite.py            # every check, in parallel; logs in suite_logs/
python suite.py --both     # also on Lua 5.5
python suite.py --only ui_smoke,lua51_lint
```

What runs:

- `lua51_lint.py`: compiles every file on Lua 5.1, fails on WoW's limits (200 locals, 60 upvalues
  per function) and on global writes; new global reads are compared with `lua51_globals.txt`
  (`--update` rewrites it, from a clean checkout).
- `forward_lint.py`, `locale_keys.py`, `locale_glyphs.py`: calls before definitions, translation keys
  and placeholders, characters the game's fonts can't draw (reads the game's font cache).
- `*_smoke.lua`: the UI driven like a player against mocked frames (`run51.py` runs them on 5.1).
- `claim_reel_test.py`, `raid_ceiling_test.py` and `../scenarios.py`, `../run.py`: the loot logic
  against the Encounter Journal model in `../`.

Tools:

- `deploy.py`: copies the addon into the game's AddOns folder as the release zip holds it.
- `bump_version.py OLD NEW`: the version in the TOC, `Core.lua` and the README badge.
- `bis/`: the Best-in-Slot refresh. Fetch the 40 Wowhead guides into `bis/markup.txt` (the in-game
  browser's fetch; see the steps in the project notes), check them with `parse.py -v`, then
  `make_bis.py PATCH BUILD` writes `Bis.lua`.
- `edits.py`: exact-match edits that keep a file's CRLF line endings.
