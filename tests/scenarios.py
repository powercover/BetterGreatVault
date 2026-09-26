"""Encounter Journal regression scenarios for Better Great Vault.

Each scenario runs in a fresh Lua runtime with tests/ej_model.lua (the client's Encounter Journal
plus Blizzard's Adventure Guide), tests/harness.lua (addon loading, UI stand-in, checks) and the
addon's non-UI files (Utils, WorldLoot, Rewards, LootTable, Core).

Checks per scenario (see harness.lua):
  a  lists equal the ground truth from the model DB (pool + difficulty + loot spec), reels too
  b  lists finish within 10 simulated seconds / 400 passes
  c  after scanning, the journal state the Adventure Guide had is back and its events are attached
  d  no Adventure Guide loot rebuild or re-select happens inside an addon call
  e  no Lua errors, no blocked actions
  f  10s of later journal events cause no rescans

Usage (from the tests folder):
  python scenarios.py                 run every scenario against the working tree
  python scenarios.py --reference     run them against tests/reference_rewards.lua (harness self-check)
  python scenarios.py --naive         the same reader without scan isolation (must fail: negative control)
  python scenarios.py -v NAME ...     run selected scenarios, printing every check's detail
  python scenarios.py --root DIR      load the addon's .lua files from DIR (e.g. an older checkout)
"""

import os
import sys
import traceback
from pathlib import Path

from lupa import LuaError, LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
CHECKS = ["a", "b", "c", "d", "e", "f"]
ALL = "R1,R2,M1,M2,W1"


class Run:
    def __init__(self, reference):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("if not unpack and table.unpack then unpack = table.unpack end")
        self.lua.execute((TESTS / "ej_model.lua").read_text(encoding="utf-8"))
        self.lua.execute((TESTS / "harness.lua").read_text(encoding="utf-8"))
        self.g = self.lua.globals()
        self.M = self.g.EJModel
        self.H = self.g.Harness
        self.AG = self.M.AG
        self.ids = self.M.ids
        self.reference = reference

    # setup ---------------------------------------------------------------------------------
    def cfg(self, key, value):
        self.M.SetCfg(key, value)

    def boot(self):
        if self.reference == "naive":
            self.g.BGV_REFERENCE_NAIVE = True
        err = self.H.Boot(bool(self.reference), TESTS.as_posix())
        if err:
            raise BootError(str(err))

    # ids -----------------------------------------------------------------------------------
    @property
    def raid(self):
        return self.ids.raid

    def raid_boss(self, index):
        return self.ids.raidBosses[index]

    def dungeon(self, index):
        return self.ids.seasonDungeons[index]

    def boss(self, instance_id, index):
        return self.M.BossOf(instance_id, index)

    # player actions ------------------------------------------------------------------------
    def ag(self, action, *args):
        getattr(self.AG, action)(*args)

    def mark(self):
        """The player is done with the Adventure Guide; its state must survive the addon."""
        self.H.MarkUser()

    def open_vault(self):
        self.H.OpenVault()

    def hover(self, name):
        self.H.Hover(name)

    def poll(self, names):
        self.H.StartPoll(names)

    def run(self, seconds):
        self.M.Run(seconds)

    def settle(self, names=ALL, seconds=20):
        return self.H.Settle(names, seconds)

    def set_loot_spec(self, spec_id):
        self.g.SetLootSpecialization(spec_id)

    def verify(self, names=ALL):
        self.H.Verify(names)

    def results(self):
        rows = []
        for line in str(self.H.ResultText()).splitlines():
            parts = line.split("\t", 2)
            while len(parts) < 3:
                parts.append("")
            rows.append(tuple(parts))
        return rows


class BootError(Exception):
    pass


# ----------------------------------------------------------------------------------------------
# Scenarios
# ----------------------------------------------------------------------------------------------

def fresh_login_no_guide(t):
    t.boot()
    t.open_vault()
    t.hover("R1")
    t.run(0.5)
    t.hover("M1")
    t.verify()


def cold_journal_login(t):
    """Every instance's loot list still loading at login (0 rows, out of date, arrives later)."""
    t.M.SetAllCold()
    t.boot()
    t.open_vault()
    t.hover("M1")
    t.verify()


def guide_opened_closed(t):
    t.boot()
    t.ag("Open")
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R1")
    t.run(0.3)
    t.hover("M1")
    t.verify()


def guide_raid_instance(t):
    t.boot()
    t.ag("Open")
    t.ag("PickTab", "raids")
    t.ag("PickInstance", t.raid)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R1")
    t.run(0.3)
    t.hover("M1")
    t.verify()


def guide_raid_boss_mythic(t):
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(8))
    t.ag("SetDifficulty", 16)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R2")
    t.run(0.3)
    t.hover("M1")
    t.verify()


def user_repro(t):
    """Open the guide, pick a dungeon boss, change difficulty, close; open the vault, hover the
    raid slot, then the Mythic+ slot."""
    t.boot()
    t.ag("Open")
    t.ag("PickTab", "dungeons")
    dungeon = t.dungeon(3)
    t.ag("PickInstance", dungeon)
    t.ag("PickBoss", t.boss(dungeon, 2))
    t.ag("SetDifficulty", 23)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R1")
    t.run(1.0)
    t.hover("M1")
    t.run(1.0)
    t.verify()


def user_repro_select_keeps_instance(t):
    t.cfg("crossInstanceEncounter", "select")
    user_repro(t)


def user_repro_select_ignored(t):
    t.cfg("crossInstanceEncounter", "ignore")
    user_repro(t)


def user_repro_select_fires_events(t):
    """Pessimistic client: EJ_SelectInstance fires EJ_LOOT_DATA_RECIEVED, and moving to a valid
    difficulty on select fires EJ_DIFFICULTY_UPDATE too."""
    t.cfg("selectFiresLootEvent", True)
    t.cfg("fireOnDifficultyFix", True)
    user_repro(t)


def no_season_tier(t):
    """No "Current Season" tier: the current expansion's tier also lists a dungeon outside the
    rotation and misses the older one that is in it."""
    t.cfg("seasonTier", False)
    t.M.ResetJournalState()
    user_repro(t)


def guide_dungeon_heroic_then_raid(t):
    t.boot()
    t.ag("Open")
    dungeon = t.dungeon(4)
    t.ag("PickInstance", dungeon)
    t.ag("SetDifficulty", 2)
    t.ag("PickBoss", t.boss(dungeon, 2))
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(2))
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("M2")
    t.run(0.5)
    t.hover("R1")
    t.verify()


def guide_older_tier(t):
    t.boot()
    t.ag("Open")
    t.ag("PickTab", "dungeons")
    t.ag("PickTier", t.M.OLD_TIER)
    old = t.ids.oldDungeon
    t.ag("PickInstance", old)
    t.ag("PickBoss", t.boss(old, 1))
    t.ag("SetDifficulty", 2)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("M1")
    t.run(0.5)
    t.hover("R1")
    t.verify()


def guide_slot_filter_trinket(t):
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(3))
    t.ag("SetSlotFilter", 13)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R1")
    t.run(0.3)
    t.hover("M1")
    t.verify()


def guide_other_class_filter(t):
    t.boot()
    t.ag("Open")
    dungeon = t.dungeon(2)
    t.ag("PickInstance", dungeon)
    t.ag("SetLootFilter", 1, 71)
    t.ag("PickBoss", t.boss(dungeon, 1))
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("M1")
    t.run(0.3)
    t.hover("R2")
    t.verify()


def guide_open_during_scan(t):
    """Claim week: the addon is idle in the vault, but the minimap loot table still lists loot
    while the Adventure Guide stays open on a raid boss (nothing closes it)."""
    t.M.weekly.canClaim = True
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(5))
    t.ag("SetDifficulty", 16)
    t.mark()
    t.poll(ALL)
    t.verify()


def loot_spec_change_mid_load(t):
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(4))
    t.ag("SetDifficulty", 15)
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("R1")
    t.run(0.1)
    t.set_loot_spec(105)
    t.run(0.2)
    t.hover("M1")
    t.verify()


def switch_raid_mplus(t):
    t.boot()
    t.ag("Open")
    dungeon = t.dungeon(5)
    t.ag("PickInstance", dungeon)
    t.ag("PickBoss", t.boss(dungeon, 3))
    t.ag("SetDifficulty", 23)
    t.ag("Close")
    t.mark()
    t.open_vault()
    for _ in range(4):
        for name in ("R1", "M1", "R2", "M2"):
            t.hover(name)
            t.run(0.05)
    t.hover("M1")
    t.verify()


def challenge_maps_late(t):
    """GetMapTable() is empty until CHALLENGE_MODE_MAPS_UPDATE (cold login)."""
    t.M.challenge.ready = False
    t.boot()
    t.open_vault()
    t.hover("M1")
    t.run(2.0)
    t.M.PublishChallengeMaps()
    t.verify()


def keystone_difficulty_invalid(t):
    """One rotation dungeon has no Mythic Keystone difficulty in the journal."""
    t.M.SetInstanceDifficulties(t.dungeon(3), t.lua.table(1, 2, 23))
    t.boot()
    t.open_vault()
    t.hover("M1")
    t.verify()


def uncached_items_late(t):
    """Half the items are not cached; rows come back as the cold-journal placeholder (instance
    name, question-mark icon) and item data arrives 0.5s after it is asked for."""
    t.M.SetUncached(2, 1)
    t.cfg("itemLoadDelay", 0.5)
    t.cfg("placeholderRows", True)
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(6))
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("M1")
    t.run(0.3)
    t.hover("R1")
    t.verify()


def dungeon_bosses_unlisted(t):
    """As seen in game: the journal lists no bosses for keystone dungeons (EJ_GetEncounterInfoByIndex
    returns nothing), though the whole dungeon's loot reads fine. M+ must still list every dungeon."""
    t.cfg("dungeonBossList", False)
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.dungeon(2))
    t.ag("Close")
    t.mark()
    t.open_vault()
    t.hover("M1")
    t.run(0.3)
    t.hover("R1")
    t.verify()


def guide_and_vault_open_together(t):
    """Progress week, nothing auto-closes any more: the Adventure Guide stays open next to the
    vault, the player browses it (dungeon boss, then a raid boss on another difficulty) between
    hovers, and the loot table keeps listing loot the whole time."""
    t.boot()
    t.ag("Open")
    t.ag("PickInstance", t.dungeon(1))
    t.ag("PickBoss", t.boss(t.dungeon(1), 2))
    t.ag("SetDifficulty", 23)
    t.open_vault()
    t.hover("M1")
    t.run(0.3)
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(3))
    t.ag("SetDifficulty", 15)
    t.mark()
    t.hover("R1")
    t.run(0.3)
    t.hover("M2")
    t.poll(ALL)
    t.verify()


SCENARIOS = [
    ("fresh_login_no_guide", fresh_login_no_guide),
    ("cold_journal_login", cold_journal_login),
    ("guide_opened_closed", guide_opened_closed),
    ("guide_raid_instance", guide_raid_instance),
    ("guide_raid_boss_mythic", guide_raid_boss_mythic),
    ("user_repro_dungeon_boss_diff", user_repro),
    ("user_repro_select_keeps_inst", user_repro_select_keeps_instance),
    ("user_repro_select_ignored", user_repro_select_ignored),
    ("user_repro_select_fires_events", user_repro_select_fires_events),
    ("no_season_tier", no_season_tier),
    ("guide_dungeon_heroic_then_raid", guide_dungeon_heroic_then_raid),
    ("guide_older_tier", guide_older_tier),
    ("guide_slot_filter_trinket", guide_slot_filter_trinket),
    ("guide_other_class_filter", guide_other_class_filter),
    ("guide_open_during_scan", guide_open_during_scan),
    ("loot_spec_change_mid_load", loot_spec_change_mid_load),
    ("switch_raid_mplus", switch_raid_mplus),
    ("challenge_maps_late", challenge_maps_late),
    ("keystone_difficulty_invalid", keystone_difficulty_invalid),
    ("uncached_items_late", uncached_items_late),
    ("dungeon_bosses_unlisted", dungeon_bosses_unlisted),
    ("guide_and_vault_open_together", guide_and_vault_open_together),
]


def run_one(name, fn, reference):
    try:
        t = Run(reference)
        fn(t)
        return t.results(), None
    except BootError as err:
        return [], "LOAD: " + str(err).splitlines()[0]
    except LuaError as err:
        return [], "LUA: " + str(err).splitlines()[0]
    except Exception:  # noqa: BLE001 - report and keep going
        return [], "PY: " + traceback.format_exc().strip().splitlines()[-1]


def main(argv):
    argv = list(argv)
    addon_root = ROOT
    if "--root" in argv:
        at = argv.index("--root")
        addon_root = Path(argv[at + 1]).resolve()
        del argv[at:at + 2]
    os.chdir(addon_root)
    reference = "naive" if "--naive" in argv else ("--reference" in argv)
    verbose = "-v" in argv or "--verbose" in argv
    wanted = [arg for arg in argv if not arg.startswith("-")]
    selected = [(n, f) for n, f in SCENARIOS if not wanted or n in wanted]
    if not selected:
        print("no scenario matches " + ", ".join(wanted))
        return 2

    width = max(len(n) for n, _ in selected)
    header = "scenario".ljust(width) + "  " + "  ".join(c.center(4) for c in CHECKS)
    label = {"naive": "NAIVE reference (no isolation)", True: "REFERENCE scanner", False: "working tree"}
    print(label[reference] + ("" if addon_root == ROOT else f" from {addon_root}") + "\n")
    print(header)
    print("-" * len(header))
    failed = 0
    details = []
    for name, fn in selected:
        rows, error = run_one(name, fn, reference)
        by_key = {key: (status, detail) for key, status, detail in rows if key in CHECKS}
        if error:
            cells = ["ERR "] * len(CHECKS)
            failed += 1
            details.append((name, "run", "ERROR", error))
        else:
            cells = []
            for key in CHECKS:
                status, detail = by_key.get(key, ("----", ""))
                cells.append(status[:4].ljust(4))
                if status == "FAIL" or verbose:
                    details.append((name, key, status, detail))
            if any(by_key.get(key, ("",))[0] == "FAIL" for key in CHECKS):
                failed += 1
            for key, status, detail in rows:
                if key == "info" and verbose:
                    details.append((name, key, status, detail))
        print(name.ljust(width) + "  " + "  ".join(cells))

    print()
    print(f"{len(selected) - failed}/{len(selected)} scenarios passed")
    if details:
        print()
        for name, key, status, detail in details:
            print(f"[{status}] {name} ({key}): {detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
