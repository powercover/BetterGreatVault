"""Writes Bis.lua from the parsed Wowhead guides (parse.py): python make_bis.py <patch> <build>"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from parse import build, read_markup  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
SPEC_ORDER = [62, 63, 64, 65, 66, 70, 71, 72, 73, 102, 103, 104, 105, 250, 251, 252, 253, 254, 255, 256, 257,
              258, 259, 260, 261, 262, 263, 264, 265, 266, 267, 268, 269, 270, 577, 581, 1467, 1468, 1473, 1480]

patch, build_no = sys.argv[1], sys.argv[2]
path = os.path.join(ROOT, "Bis.lua")
old = open(path, "rb").read().decode("utf-8").replace("\r\n", "\n")
tail = old[old.index("\n}\n") + 3:]

ranks, _ = build(read_markup())
assert sorted(ranks) == sorted(SPEC_ORDER), sorted(ranks)

out = ["local _, BGV = ...", "", "BGV.Bis = {}", "",
       "-- Wowhead Midnight Season 2 Best in Slot guides, Patch %s." % patch,
       "-- S is overall BiS (every tab of the guide's BiS table, and the items it says to catalyze).",
       "-- Trinket letters are the guide's tier list (A+ counts as A, F is left out).",
       "-- Raid and Mythic+ highlights are A, and items named in the crafting sections are B, unless a",
       "-- higher letter is already set.",
       "-- Catalyzed items keep their stats in Season 2: the raid and Mythic+ pieces a guide catalyzes into",
       "-- the class set are S, and the set piece itself, as it drops, is A. A set piece the guide wears",
       "-- as it drops stays S. Every set piece is in its class's lists, so the class always shows its set.",
       "",
       "-- The game version the guides were read for, shown in the settings next to the tiers option.",
       'BGV.Bis.SOURCE = { patch = "%s", build = "%s" }' % (patch, build_no),
       "",
       "local tiers = {"]
for spec in SPEC_ORDER:
    out.append("    [%d] = {" % spec)
    for item in sorted(ranks[spec]):
        out.append('        [%d] = "%s",' % (item, ranks[spec][item]))
    out.append("    },")
out.append("}")
text = "\n".join(out) + "\n\n" + tail.lstrip("\n")
open(path, "wb").write(text.replace("\n", "\r\n").encode("utf-8"))
print("Bis.lua", sum(len(r) for r in ranks.values()), "entries")
