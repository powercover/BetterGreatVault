"""Rewards.ClaimIcons against the Encounter Journal model (tests/ej_model.lua): a reward's reel at the
vault holds only items its slot could have awarded. Raid: the bosses of the reward's raid up to the
first one that drops it; Mythic+: every season dungeon; world: the season's world gear."""
import sys
from pathlib import Path

import os
TESTS = Path(os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))) / "tests"
sys.path.insert(0, str(TESTS))
os.chdir(TESTS.parent)
import scenarios  # noqa: E402

fails = 0


def check(ok, message):
    global fails
    if not ok:
        fails += 1
        print("CLAIM REEL FAIL:", message)


def settle(run, info, reward):
    icons, pending = None, True
    for _ in range(300):
        icons, pending = run.H.BGV.Rewards.ClaimIcons(info, reward)
        if not pending:
            break
        run.M.Run(0.1)
    return [icons[k].itemID for k in sorted(icons.keys())] if icons else [], pending


def item_named(run, name):
    for item_id, item in run.M["items"].items():
        if item.name == name:
            return item_id
    raise KeyError(name)


def loot_of(run, instance_id, upto=None):
    instance = run.M.instances[instance_id]
    ids = set()
    bosses = [instance.bosses[k] for k in sorted(instance.bosses.keys())]
    for position, boss_id in enumerate(bosses, start=1):
        if upto is not None and position > upto:
            break
        boss = run.M.bosses[boss_id]
        ids.update(boss.loot[k] for k in boss.loot.keys())
    return ids


run = scenarios.Run(False)
run.boot()
lua = run.lua
utils = run.H.BGV.Utils
raid_type, mplus_type, world_type = utils.ThresholdType("Raid"), utils.ThresholdType("Activities"), utils.ThresholdType("World")
raid_id = run.ids.raid

# --- raid: the reward drops from boss 4: bosses 1 to 4 of its raid, nothing past them ---------------------------
reward = item_named(run, "Voidspire B4 Cloak")
info = lua.table_from({"type": raid_type, "index": 1})
items, pending = settle(run, info, reward)
upto4, all8 = loot_of(run, raid_id, 4), loot_of(run, raid_id)
later_only = all8 - upto4
own = [i for i in items if i in all8]
check(not pending, "raid: the lists settle")
check(reward in items, "raid: the reward itself is among them")
check(len(own) >= 6, "raid: a real pool, not a handful: %d items" % len(own))
check(not any(i in later_only for i in items), "raid: nothing from the bosses after the reward's: %s" % [i for i in items if i in later_only])
check(any(i in loot_of(run, raid_id, 1) for i in items), "raid: the first boss's loot is in it")
check(not any(run.M["items"][i].nonGear for i in own), "raid: gear only (no tokens or mounts)")
print("raid reel:", len(items), "items,", len(own), "from bosses 1-4")

# --- raid, a Heroic slot: read at Heroic, so nothing that only drops on Mythic ------------------------------------
heroic = lua.table_from({"type": raid_type, "index": 1, "level": 15})
items, pending = settle(run, heroic, reward)
mythic_only = [i for i in items if i in all8 and not run.M.Drops(run.M["items"][i], 15)]
check(not pending and reward in items, "raid, Heroic slot: the list settles, the reward in it")
check(not mythic_only, "raid, Heroic slot: nothing that only drops on Mythic: %s" % mythic_only)

# --- raid: the first boss's reward: that boss only -----------------------------------------------------------------
first = item_named(run, "Voidspire B1 Cloak")
items, pending = settle(run, info, first)
own = [i for i in items if i in all8]
check(own and all(i in loot_of(run, raid_id, 1) for i in own), "raid, first boss's reward: only that boss's loot")

# --- raid: a reward the journal doesn't list (a class set piece): no raid loot at all -----------------------------
items, pending = settle(run, info, 999999)
check(not any(i in all8 for i in items), "raid, a reward from no boss: no raid loot guessed")

# --- Mythic+: every season dungeon --------------------------------------------------------------------------------
season = set()
for k in sorted(run.ids.seasonDungeons.keys()):
    season |= loot_of(run, run.ids.seasonDungeons[k])
info = lua.table_from({"type": mplus_type, "index": 1, "activityTierID": 256})
items, pending = settle(run, info, 0)
dungeon_items = [i for i in items if i in season]
check(not pending and len(dungeon_items) >= 10, "Mythic+: the season's dungeons' loot: %d items" % len(dungeon_items))
check(not any(i in all8 for i in items), "Mythic+: no raid loot")
print("Mythic+ reel:", len(items), "items")

# --- world: the season's world gear ---------------------------------------------------------------------------------
info = lua.table_from({"type": world_type, "index": 1})
items, pending = settle(run, info, 0)
check(not pending and len(items) >= 4, "world: world gear: %d items" % len(items))
check(not any(i in all8 or i in season for i in items), "world: no raid or dungeon loot")
print("world reel:", len(items), "items")

# --- world: an ID the game has no record of is left out, and an item whose specs never answer is left out
# in time; either way the list settles with the real items ---------------------------------------------------------
world_loot = run.H.BGV.WorldLoot
silent = world_loot[1]
world_loot[len(world_loot) + 1] = 999999
lua.execute("""
local getSpecs = C_Item.GetItemSpecInfo or GetItemSpecInfo
C_Item.GetItemSpecInfo = function(itemID, ...)
  if itemID == %d then return nil end
  return getSpecs(itemID, ...)
end
""" % silent)
run.H.BGV.Rewards.InvalidateIcons()
before = len(items)
items, pending = settle(run, info, 0)
check(not pending, "world, an unknown ID and a silent item: the list still settles")
check(999999 not in items and silent not in items, "world: neither is listed")
check(len(items) >= before - 1, "world: the real items still are: %d of %d" % (len(items), before))

# --- nothing to go on: nothing ---------------------------------------------------------------------------------------
items, pending = settle(run, None, 0)
check(items == [] and not pending, "no slot info: an empty list")

# --- one reading budget for a whole pass: every reel of the vault's reveal shares it, so a pass reads
# about one budget's worth of the journal however many rewards there are. Spent (limit 0: one read,
# then no more), the next reel reads nothing and waits; a new budget reads again -------------------------
fresh = scenarios.Run(False)
fresh.boot()
rewards, model = fresh.H.BGV.Rewards, fresh.M
raid_info = fresh.lua.table_from({"type": raid_type, "index": 1})
mplus_info = fresh.lua.table_from({"type": mplus_type, "index": 1, "activityTierID": 256})
shared = rewards.NewReadBudget(0)
def selects():
    """EJ_SelectInstance calls so far, whoever the model credits them to (a direct call from here
    counts as the client's)."""
    return sum(model.CallCount(owner, "EJ_SelectInstance") for owner in ("addon", "client", "ag"))


before = selects()
rewards.ClaimIcons(raid_info, item_named(fresh, "Voidspire B4 Cloak"), shared)
after_raid = selects()
check(after_raid > before, "a shared budget: the first reel reads the journal")
icons, pending = rewards.ClaimIcons(mplus_info, 0, shared)
check(selects() == after_raid and pending,
      "the budget spent: the next reel reads nothing and waits (%d -> %d)" % (after_raid, selects()))
icons, pending = rewards.ClaimIcons(mplus_info, 0, rewards.NewReadBudget(0))
check(selects() > after_raid, "a new budget: it reads again")

print("claim reel checks passed" if fails == 0 else "%d claim reel checks failed" % fails)
