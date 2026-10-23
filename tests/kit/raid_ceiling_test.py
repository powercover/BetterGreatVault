"""The raid Mythic ceiling against the Encounter Journal model (tests/ej_model.lua): a Mythic raid slot
whose reward link shows the ceiling (344) lists at the ceiling only the loot of the raid's last two
bosses that were themselves killed on Mythic; every other boss's loot at the normal cap (334). A
Raid Finder kill is never a Mythic kill, though its difficulty ID (17) is above Mythic's (16)."""
import os
import sys
from pathlib import Path

TESTS = Path(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))) / "tests"
sys.path.insert(0, str(TESTS))
os.chdir(TESTS.parent)
import scenarios  # noqa: E402

fails = 0


def check(ok, message):
    global fails
    if not ok:
        fails += 1
        print("RAID CEILING FAIL:", message)


def levels_by_boss(kills, season=None, link_level=344):
    run = scenarios.Run(False)
    run.H.RAID_KILLS = run.lua.table_from(kills)
    run.boot()
    if season:
        run.M.mythicPlus.season = season
    slot = run.H.slots.R1
    slot.itemLevel = link_level  # the vault's reward link
    rewards = run.H.BGV.Rewards
    entries, pending = None, True
    for _ in range(300):
        entries, pending = rewards.ItemsForSlot(slot)
        if not pending:
            break
        run.M.Run(0.1)
    check(not pending, "%s: the list settles" % (kills,))
    level_of = {}
    for k in sorted(entries.keys()):
        entry = entries[k]
        level_of[entry.itemID] = entry.itemLevel
    # each boss's own loot: items no other boss drops (a shared item is at the ceiling when any boss
    # that drops it was a Mythic kill of the last two)
    bosses = [run.M.bosses[run.ids.raidBosses[k]] for k in sorted(run.ids.raidBosses.keys())]
    loot = [set(boss.loot[k] for k in boss.loot.keys()) for boss in bosses]
    out = {}
    for position, own in enumerate(loot, start=1):
        others = set().union(*(l for i, l in enumerate(loot, start=1) if i != position))
        out[position] = sorted({level_of[i] for i in own - others if i in level_of})
    return out


# boss 7 killed only on Raid Finder, boss 8 on Mythic: only boss 8's loot at the ceiling
got = levels_by_boss([16, 16, 16, 16, 16, 16, 17, 16])
check(got[8] == [344], "a Mythic kill of the last boss: its loot at 344: %s" % got[8])
check(got[7] == [334], "the second-to-last boss killed only on Raid Finder: its loot at 334, not 344: %s" % got[7])
check(all(got[b] in ([334], []) for b in range(1, 7)), "earlier bosses at 334: %s" % {b: got[b] for b in range(1, 7)})

# the last two killed only on Raid Finder (the slot's Mythic kills end at boss 6): nothing at the ceiling
got = levels_by_boss([16, 16, 16, 16, 16, 16, 17, 17])
check(all(344 not in levels for levels in got.values()), "no Mythic kill of the last two bosses: nothing at 344: %s" % got)

# both last bosses on Mythic: both at the ceiling
got = levels_by_boss([16, 16, 16, 16, 16, 16, 16, 16])
check(got[7] == [344] and got[8] == [344], "both last bosses killed on Mythic: their loot at 344: %s, %s" % (got[7], got[8]))

# another season: the rule (334, 344 for the last two) stands down; the reward link's level stands
got = levels_by_boss([16, 16, 16, 16, 16, 16, 17, 16], season=19, link_level=350)
check(all(levels in ([350], []) for levels in got.values()), "another season: the link's 350 for every boss: %s" % got)

print("raid ceiling checks passed" if fails == 0 else "%d raid ceiling checks failed" % fails)
