"""Encounter Journal regression scenarios for Better Great Vault.

Each scenario runs in a fresh Lua runtime with tests/ej_model.lua (the client's Encounter Journal
plus Blizzard's Adventure Guide), tests/harness.lua (addon loading, UI stand-in, checks) and the
addon's non-UI files (Utils, WorldLoot, Rewards, LootTable, Core).

Checks per vault scenario (see harness.lua):
  a  lists equal the ground truth from the model DB (pool + difficulty + loot spec), reels too
  b  lists finish within 10 simulated seconds / 400 passes
  c  after scanning, the journal state the Adventure Guide had is back and its events are attached
  d  no Adventure Guide loot rebuild or re-select happens inside an addon call
  e  no Lua errors, no blocked actions
  f  10s of later journal events cause no rescans

Checks per loot database scenario (Rewards.DatabaseLevels / DatabaseItems / ClearDatabase):
  itm  items equal the ground truth for the class/spec filter over the whole season (every raid
       boss), at the in-game item level tables, raid Mythic's last two bosses at the ceiling
  lvl  DatabaseLevels tables equal the in-game data
  rst  every database call leaves the journal and the guide as they were (no guide rebuilds)
  vlt  vault lists untouched by database browsing and the reverse (same results, no extra calls)
  prf  settled database lists make no journal calls
  clr  ClearDatabase drops the database's caches, not the vault's
  rec  lists recover from a loot spec change / InvalidateIcons / ClearDatabase mid-load
  err  no Lua errors

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
DB_CHECKS = ["itm", "lvl", "rst", "vlt", "prf", "clr", "rec", "err"]
ALL = "R1,R2,M1,M2,W1"

# Classes and specs in the model: Warrior 1 (71 Arms, 72 Fury, 73 Protection), Priest 5 (256, 257,
# 258), Mage 8 (62, 63, 64), Druid 11 (the player: 102 Balance, 103, 104, 105 Restoration).


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

    # loot database -------------------------------------------------------------------------
    def boot_db(self):
        self.boot()
        rewards = self.H.BGV.Rewards
        missing = [name for name in ("DatabaseLevels", "DatabaseItems", "ClearDatabase") if rewards[name] is None]
        if missing:
            raise BootError("no loot database API: BGV.Rewards." + ", ".join(missing) + " missing")

    def db_start(self, lists):
        """Database lists the loot table polls: "source/level/classID/specID", comma separated."""
        self.H.DbStart(lists)

    def db_settle(self, seconds=20):
        return self.H.DbSettle(seconds)

    def db_items(self):
        self.H.DbCheckItems()

    def levels(self, *sources):
        for source in sources:
            self.H.CheckLevels(source)

    def expect(self, source, level, item_level):
        """The item level the game has shown for a level (None: not known)."""
        self.H.DbExpect(source, level, item_level)

    def slot(self, name, field, value):
        self.H.SetSlot(name, field, value)

    def db_report(self):
        self.H.DbReport()

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


# ----------------------------------------------------------------------------------------------
# Loot database scenarios (Rewards.DatabaseLevels / DatabaseItems / ClearDatabase)
# ----------------------------------------------------------------------------------------------

def db_other_classes(t):
    """Another class, one spec then all specs, for every source and several levels: items equal
    the truth for that filter over every raid boss, at the in-game item levels (none where the
    game gives none), raid Mythic's last two bosses at the ceiling. Then settled lists are read
    again and again with no journal calls."""
    t.boot_db()
    t.db_start("raid/16/1/73,raid/15/1/73,raid/17/1/73,mplus/8/1/73,mplus/2/1/73,world/8/1/73,world/1/1/73")
    t.db_settle()
    t.db_items()
    t.db_start("raid/16/1/0,raid/14/1/0,mplus/10/1/0,mplus/4/1/0,world/8/1/0,world/2/1/0")
    t.db_settle()
    t.db_items()
    t.db_start("raid/16/8/63,mplus/7/8/0,world/5/8/63,raid/16/5/0,mplus/9/5/258,world/3/5/0")
    t.db_settle()
    t.db_items()
    t.H.CheckDbPerf(3)
    t.db_report()


def db_all_classes(t):
    """"All classes" (class 0, the journal's own all-classes filter): every source lists every
    class's loot, including gear the player can't equip, at the in-game item levels; switching
    back to one class afterwards gives that class's list again."""
    t.boot_db()
    t.db_start("raid/16/0/0,raid/15/0/0,mplus/10/0/0,mplus/7/0/0,world/8/0/0,world/3/0/0")
    t.db_settle()
    t.db_items()
    t.H.CheckFlaggedListed()
    t.db_start("raid/16/8/0,mplus/10/8/63,world/8/8/0")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_equip_flags(t):
    """The player is a Druid: the journal flags plate, swords and shields on every row it lists
    (handError / weaponTypeError describe the character looking). Browsing Mage, Paladin and
    Warrior loot still lists them: the flags don't apply to another class's list."""
    t.boot_db()
    t.db_start("raid/16/8/0,raid/16/2/0,raid/15/2/66,raid/16/1/73,mplus/8/2/70,mplus/8/8/63,mplus/10/1/0,world/8/2/0")
    t.db_settle()
    t.db_items()
    t.H.CheckFlaggedListed()
    t.db_report()


def db_guide_restored(t):
    """While the Adventure Guide is open on a dungeon boss at Mythic with a Priest/Shadow class
    filter and a Trinket slot filter (then closed, then open on a raid boss), every database call
    leaves the journal and the guide exactly as they were, and the guide never rebuilds."""
    t.boot_db()
    t.ag("Open")
    dungeon = t.dungeon(2)
    t.ag("PickInstance", dungeon)
    t.ag("SetDifficulty", 23)
    t.ag("PickBoss", t.boss(dungeon, 3))
    t.ag("SetLootFilter", 5, 258)
    t.ag("SetSlotFilter", 13)
    t.db_start("raid/16/1/73,mplus/8/8/0,world/8/11/0,raid/14/11/0")
    t.db_settle()
    t.db_items()
    t.ag("Close")
    t.db_start("raid/15/5/0,mplus/4/1/71")
    t.db_settle()
    t.db_items()
    t.ag("Open")
    t.ag("PickInstance", t.raid)
    t.ag("PickBoss", t.raid_boss(7))
    t.ag("SetDifficulty", 16)
    t.ag("ResetLootFilter")
    t.db_start("raid/16/2/0,mplus/10/11/104")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_no_guide_after_vault(t):
    """No guide ever loaded: the vault's scans leave an instance selected in the journal, and each
    database call puts that selection (read back from the journal's link) and the filters back."""
    t.boot_db()
    t.open_vault()
    t.hover("R1")
    t.settle()
    t.db_start("raid/16/1/73,mplus/8/5/0,world/8/8/0")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_vault_isolation(t):
    """Database lists first (including the player's own class and loot spec), then the vault's:
    the database lists are unchanged and need no journal calls. Vault lists marked, the database
    browsed for other classes: the vault lists are unchanged with no extra journal calls."""
    t.boot_db()
    t.db_start("raid/16/11/102,mplus/8/11/102,world/8/11/102,raid/15/1/0,mplus/2/8/62")
    t.db_settle()
    t.H.MarkDb()
    t.open_vault()
    t.hover("R1")
    t.run(0.3)
    t.hover("M1")
    t.settle()
    t.H.CheckDb("after the vault's lists loaded")
    t.H.MarkVault(ALL)
    t.db_start("raid/16/1/73,raid/17/5/0,mplus/8/1/0,mplus/5/5/257,world/8/8/63,world/1/5/0")
    t.db_settle()
    t.H.CheckVault("after browsing the database")
    t.H.CheckDbPerf(3)
    t.db_report()


def db_clear_and_invalidate(t):
    """InvalidateIcons (a loot spec change) keeps the database's reads and only rebuilds its level
    tables. ClearDatabase (the window closing) drops the database's reads, levels, raid scope and
    world spec answers, but the vault's lists stay warm; the database settles to the same lists."""
    t.boot_db()
    t.open_vault()
    t.hover("R1")
    t.settle()
    t.db_start("raid/16/1/73,mplus/8/8/0,world/8/5/0,world/4/2/66")
    t.db_settle()
    t.H.CheckInvalidateKeepsDb()
    # The vault's lists were dropped: the loot table re-reads them.
    t.poll(ALL)
    t.settle()
    t.H.StopPoll()
    t.H.MarkVault(ALL)
    t.db_settle()
    t.H.MarkDb()
    t.H.CheckClear()
    t.db_items()
    t.db_report()


def db_spec_change_recovery(t):
    """Database lists loading (half the items not cached, slow item data) while the loot spec
    changes (PLAYER_LOOT_SPEC_UPDATED -> InvalidateIcons), InvalidateIcons runs again and the
    database is cleared (window closed and reopened): every list finishes again, correct, and the
    vault's lists follow the new loot spec."""
    t.M.SetUncached(2, 1)
    t.cfg("itemLoadDelay", 0.4)
    t.boot_db()
    t.open_vault()
    t.hover("M1")
    t.db_start("raid/16/1/73,mplus/8/8/0,world/8/5/0,raid/15/11/0")
    t.run(0.3)
    t.set_loot_spec(105)
    t.run(0.3)
    t.H.Invalidate()
    t.run(0.2)
    t.H.ClearDatabase()
    t.poll(ALL)
    t.db_settle()
    t.H.CheckDbRecovery()
    t.db_items()
    t.settle()
    t.H.CheckVaultTruth(ALL)
    t.db_report()


def db_nested_read(t):
    """Another addon calls DatabaseItems from a journal event fired inside our scan (a nested read
    with its own class filter), twice: at the scan's loot filter switch and inside a later journal
    change. The outer read keeps its own filter (a raid list, then the vault's own lists), both
    lists come out right, and the journal and the guide are restored."""
    t.boot_db()
    t.ag("Open")
    t.ag("PickInstance", t.dungeon(1))
    t.ag("PickBoss", t.boss(t.dungeon(1), 1))
    t.ag("Close")
    t.H.ArmNestedRead("mplus/8/5/0", 2)
    t.db_start("raid/16/1/73")
    t.db_settle()
    t.H.CheckNestedReads()
    t.H.ArmNestedRead("raid/15/2/0", 2)
    t.open_vault()
    t.hover("R1")
    t.settle()
    t.H.CheckVaultTruth("R1,M1", "itm")
    t.H.CheckNestedReads()
    t.db_start("raid/16/1/73,mplus/8/5/0,raid/15/2/0")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_raid_scope_late(t):
    """The vault's raid boss list (GetActivityEncounterInfo) arrives after the database opened:
    until it does, the raid lists report loading instead of finishing empty; then they fill in."""
    t.M.weekly.encounterInfoReady = False
    t.boot_db()
    t.db_start("raid/16/11/0,raid/15/1/73")
    t.run(1.0)
    t.H.DbCheckLoading("before the raid boss list arrived")
    t.M.weekly.encounterInfoReady = True
    t.M.Fire("WEEKLY_REWARDS_UPDATE")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_levels_real_data(t):
    """The user's in-game data: keystones +4..+10 and world tiers 2..8 from the vault's steps
    (+8 = 315); +2/+3 and world tier 1 have no step and no slot, so they're unknown; raid Heroic
    from the vault's Heroic slot, LFR and Normal unknown, Mythic 334 (344 ceiling). Items at an
    unknown level still come back, with no item level."""
    t.boot_db()
    t.levels("raid", "mplus", "world")
    t.db_start("mplus/3/1/73,world/1/8/0,raid/17/2/0")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_levels_below_first_step(t):
    """The vault reports a level below its first step (GetNextActivitiesIncrease(tier, -1)): +2/+3
    and world tier 1 take that item level."""
    t.M.weekly.belowZero[256] = t.lua.table(2, 305)
    t.M.weekly.belowZero[249] = t.lua.table(1, 279)
    t.boot_db()
    t.expect("mplus", 2, 305)
    t.expect("mplus", 3, 305)
    t.expect("world", 1, 279)
    t.levels("mplus", "world")
    t.db_start("mplus/2/11/0,world/1/11/0")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_levels_learned_fill_gaps(t):
    """A keystone slot resolved at +2 fills +2/+3 (below the first step); a slot at +10 whose item
    level disagrees with the step doesn't override it (live steps first)."""
    t.boot_db()
    t.H.AddSlot("M3", "Activities", 3, 2, 305, 256)
    t.slot("M1", "itemLevel", 999)
    t.expect("mplus", 2, 305)
    t.expect("mplus", 3, 305)
    t.levels("mplus")
    t.db_report()


def db_levels_world_tier1(t):
    """World tier 1 (below the first step) is unknown while the vault's tier-1 world slot hasn't
    resolved, and takes the slot's item level once it has."""
    t.boot_db()
    t.slot("W1", "level", 1)
    t.slot("W1", "itemLevel", None)
    t.levels("world")
    t.slot("W1", "itemLevel", 279)
    t.H.ClearDatabase()
    t.expect("world", 1, 279)
    t.levels("world")
    t.db_start("world/1/11/0,world/1/1/73")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_levels_raid_slots(t):
    """Raid difficulties other than Mythic are known only from a resolved vault slot at that
    difficulty: none while the Heroic slot hasn't resolved; Normal and Heroic once slots have."""
    t.boot_db()
    t.slot("R2", "itemLevel", None)
    t.expect("raid", 15, None)
    t.levels("raid")
    t.H.AddRaidSlot("R3", 14, 298)
    t.slot("R2", "itemLevel", 311)
    t.H.ClearDatabase()
    t.expect("raid", 14, 298)
    t.expect("raid", 15, 311)
    t.levels("raid")
    t.db_start("raid/14/5/257,raid/17/5/257")
    t.db_settle()
    t.db_items()
    t.db_report()


def db_levels_no_tiers(t):
    """No keystone or world tier learned (GetActivities lists none), no GetNextMythicPlusIncrease,
    no resolved keystone or world slot: every M+ and World level is unknown and there's no default,
    nothing is guessed; items still come back, with no item level. Once the keystone fallback API
    answers, the keystone steps come from it."""
    t.M.weekly.activities = t.lua.table()
    t.M.SetApiPresent("C_WeeklyRewards", "GetNextMythicPlusIncrease", False)
    t.boot_db()
    t.slot("M1", "itemLevel", None)
    t.slot("W1", "itemLevel", None)
    t.H.DbExpectSteps("mplus", False)
    t.H.DbExpectSteps("world", False)
    t.levels("mplus", "world")
    t.db_start("mplus/8/1/73,world/8/11/0")
    t.db_settle()
    t.db_items()
    t.M.SetApiPresent("C_WeeklyRewards", "GetNextMythicPlusIncrease", True)
    t.H.ClearDatabase()
    t.H.DbExpectSteps("mplus", True)
    t.levels("mplus")
    t.db_report()


def db_levels_claim_week(t):
    """Claim week: the tiers are still learned from GetActivities (keystone and world steps known),
    but the vault's slots show the items rolled, not a level: raid Heroic stays unknown."""
    t.M.weekly.canClaim = True
    t.boot_db()
    t.expect("raid", 15, None)
    t.levels("raid", "mplus", "world")
    t.db_report()


def db_levels_persisted(t):
    """Tiers and levels learned this season are kept (saved variables) when the vault stops listing
    them; a new season drops them."""
    t.boot_db()
    t.levels("mplus")
    rows = t.lua.table(t.lua.table_from({"type": 3, "index": 1, "level": 15, "activityTierID": 0,
                                         "progress": 2, "threshold": 2, "id": 1002}))
    t.M.weekly.activities = rows
    t.M.SetApiPresent("C_WeeklyRewards", "GetNextMythicPlusIncrease", False)
    t.slot("M1", "itemLevel", None)
    t.H.ClearDatabase()
    t.levels("mplus")
    t.M.mythicPlus.season = 16
    t.H.ClearDatabase()
    t.H.DbExpectSteps("mplus", False)
    t.levels("mplus")
    t.db_report()


def db_levels_heroic_tier_last(t):
    """GetActivities lists a heroic-dungeon row after the keystone rows (its own tier, answering
    its own steps): the keystone tier is still the one the levels come from."""
    t.M.AddActivity(1, 3, 0, 900, 4, 8)
    t.M.weekly.steps[900] = t.lua.table(t.lua.table(1, 272))
    t.boot_db()
    t.levels("mplus")
    t.db_report()


DB_SCENARIOS = [
    ("db_other_classes", db_other_classes),
    ("db_all_classes", db_all_classes),
    ("db_equip_flags", db_equip_flags),
    ("db_guide_restored", db_guide_restored),
    ("db_no_guide_after_vault", db_no_guide_after_vault),
    ("db_vault_isolation", db_vault_isolation),
    ("db_clear_and_invalidate", db_clear_and_invalidate),
    ("db_spec_change_recovery", db_spec_change_recovery),
    ("db_nested_read", db_nested_read),
    ("db_raid_scope_late", db_raid_scope_late),
    ("db_levels_real_data", db_levels_real_data),
    ("db_levels_below_first_step", db_levels_below_first_step),
    ("db_levels_learned_fill_gaps", db_levels_learned_fill_gaps),
    ("db_levels_world_tier1", db_levels_world_tier1),
    ("db_levels_raid_slots", db_levels_raid_slots),
    ("db_levels_no_tiers", db_levels_no_tiers),
    ("db_levels_claim_week", db_levels_claim_week),
    ("db_levels_persisted", db_levels_persisted),
    ("db_levels_heroic_tier_last", db_levels_heroic_tier_last),
]


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


def run_group(title, scenarios, checks, reference, verbose, details):
    """Runs a group of scenarios, printing one table row each; returns how many failed."""
    width = max(len(n) for n, _ in scenarios)
    header = title.ljust(width) + "  " + "  ".join(c.center(4) for c in checks)
    print(header)
    print("-" * len(header))
    failed = 0
    for name, fn in scenarios:
        rows, error = run_one(name, fn, reference)
        by_key = {key: (status, detail) for key, status, detail in rows if key in checks}
        if error:
            cells = ["ERR "] * len(checks)
            failed += 1
            details.append((name, "run", "ERROR", error))
        else:
            cells = []
            for key in checks:
                status, detail = by_key.get(key, ("----", ""))
                cells.append(status[:4].ljust(4))
                if status == "FAIL" or (verbose and status != "----"):
                    details.append((name, key, status, detail))
            if any(by_key.get(key, ("",))[0] == "FAIL" for key in checks):
                failed += 1
            for key, status, detail in rows:
                if key == "info" and verbose:
                    details.append((name, key, status, detail))
        print(name.ljust(width) + "  " + "  ".join(cells))
    print()
    return failed


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
    vault = [(n, f) for n, f in SCENARIOS if not wanted or n in wanted]
    database = [(n, f) for n, f in DB_SCENARIOS if not wanted or n in wanted]
    if not vault and not database:
        print("no scenario matches " + ", ".join(wanted))
        return 2

    label = {"naive": "NAIVE reference (no isolation)", True: "REFERENCE scanner", False: "working tree"}
    print(label[reference] + ("" if addon_root == ROOT else f" from {addon_root}") + "\n")
    failed = 0
    details = []
    if vault:
        failed += run_group("vault scenario", vault, CHECKS, reference, verbose, details)
    if database:
        failed += run_group("database scenario", database, DB_CHECKS, reference, verbose, details)

    total = len(vault) + len(database)
    print(f"{total - failed}/{total} scenarios passed")
    if details:
        print()
        for name, key, status, detail in details:
            print(f"[{status}] {name} ({key}): {detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
