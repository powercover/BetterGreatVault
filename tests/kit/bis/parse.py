"""Parses Wowhead's BiS guide markup (markup.txt, beside this file) into per-spec ranks, the way Bis.lua is built.

Rules (Bis.lua's header):
- S: every item in a BiS table row (all tabs), and every item a guide says to catalyze.
- A catalyzed row's set piece is A (the plain piece as it drops); a set piece the guide wears as
  it drops (no original-item) stays S.
- Raid and Mythic+ highlights are A unless a higher letter is already set.
- Trinkets: the guide's tier list letter (A+ counts as A; F is left out).
- Items named in the crafting sections are B unless higher.
- Every class set piece is at least A, so the class always shows its set.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
ORDER = "SABCD"

CLASS_OF = {}
for cls, specs in {1: (71, 72, 73), 2: (65, 66, 70), 3: (253, 254, 255), 4: (259, 260, 261), 5: (256, 257, 258),
                   6: (250, 251, 252), 7: (262, 263, 264), 8: (62, 63, 64), 9: (265, 266, 267), 10: (268, 269, 270),
                   11: (102, 103, 104, 105), 12: (577, 581, 1480), 13: (1467, 1468, 1473)}.items():
    for sp in specs:
        CLASS_OF[sp] = cls
BASE = {1: 271454, 2: 271463, 6: 271472, 7: 271481, 3: 271490, 13: 271499, 4: 271508, 10: 271517, 11: 271526,
        12: 271535, 9: 271544, 5: 271553, 8: 271562}
OFFSETS = (0, 1, 2, 3, 5)


def set_pieces(spec):
    base = BASE[CLASS_OF[spec]]
    return {base + o for o in OFFSETS}


def read_markup(path=None):
    s = open(path or os.path.join(HERE, "markup.txt"), encoding="utf-8").read()
    parts = re.split(r"=====SPEC (\d+) (\S*)\n", s)
    out = {}
    for i in range(1, len(parts), 3):
        out[int(parts[i])] = {"updated": parts[i + 1], "markup": parts[i + 2]}
    return out


def uncomment(s):
    return re.sub(r"<!--.*?-->", "", s, flags=re.S)


def bis_block(m):
    a = m.find("name=bis_items")
    if a < 0:
        return None
    b = m.find("[/tabs]", a)
    return m[a:b]


def table_rows(body):
    rows = []
    for table in re.findall(r"\[table[^\]]*\](.*?)\[/table\]", body, re.S):
        for chunk in table.split("[tr]")[1:]:
            r = chunk.split("[/tr]")[0]
            cells = [re.sub(r"^[^\]]*\]", "", c).split("[/td]")[0] for c in r.split("[td")[1:]]
            if len(cells) < 2:
                continue
            cell = next((c for c in cells[1:] if re.search(r"\[item=\d", c)), None)
            if cell is None:
                continue
            items = []
            for mm in re.finditer(r"\[item=(\d+)([^\]]*)\]", cell):
                o = re.search(r"original-item=(\d+)", mm.group(2))
                items.append((int(mm.group(1)), int(o.group(1)) if o else None))
            label = re.sub(r"\s+", " ", re.sub(r"\[[^\]]*\]", "", cells[0])).strip()
            rows.append((label, items))
    return rows


def catalyze_items(m):
    ids = []
    for c in re.finditer(r"Best Gear to Catalyze", m):
        head_end = m.find("[/h3]", c.start())
        ends = [m.find(x, head_end) for x in ("[/grid]", "[/tab]", "[/tabs]", "[h2", "[h3")]
        end = min(e for e in ends if e > 0)
        ids += [int(x) for x in re.findall(r"\[(?:icon-badge|item)=(\d+)", m[head_end:end])]
    return ids


def section(m, title_pat):
    a = re.search(r"\[h2[^\]]*\][^\[]*(?:\[[^\]]*\][^\[]*)*?" + title_pat, m)
    if not a:
        return ""
    b = m.find("[h2", a.end())
    return m[a.end():b if b > 0 else len(m)]


def highlights(m):
    ids = []
    for pat in (r"Best Gear from Raids", r"Best Gear from Mythic\+"):
        sec = section(m, pat)
        ids += [int(x) for x in re.findall(r"\[(?:icon-badge|item)=(\d+)", sec)]
    return ids


def trinket_tiers(m):
    out = {}
    tl = m.find("[tier-list")
    if tl < 0:
        return out, []
    end = m.find("[/tier-list]", tl)
    labels = []
    for t in re.finditer(r"\[tier\](.*?)\[/tier\]", m[tl:end], re.S):
        label = re.search(r"\[tier-label[^\]]*\](.*?)\[/tier-label\]", t.group(1), re.S).group(1).strip()
        label = re.sub(r"\[[^\]]*\]", "", label).strip()
        labels.append(label)
        for x in re.findall(r"\[(?:icon-badge|item)=(\d+)", t.group(1)):
            out.setdefault(int(x), label)
    return out, labels


def crafted_items(m):
    """Items named in the crafting sections (crafted gear, crafting order, embellishments): B."""
    ids = []
    heads = list(re.finditer(r"\[(h[23])[^\]]*\](.*?)\[/h[23]\]", m, re.S))
    for n, h in enumerate(heads):
        title = re.sub(r"\[[^\]]*\]", "", h.group(2))
        if not re.search(r"Craft|Embellish", title):
            continue
        end = heads[n + 1].start() if n + 1 < len(heads) else len(m)
        ids += [int(x) for x in re.findall(r"\[(?:icon-badge|item)=(\d+)", m[h.end():end])]
    return ids


def letter_of(label):
    l = label.strip().upper()
    if l.startswith("S"):
        return "S"
    if l and l[0] in "ABCD":
        return l[0]
    return None


def build(markups):
    ranks, notes = {}, {}
    for spec, d in markups.items():
        m = uncomment(d["markup"])
        r = {}
        note = notes.setdefault(spec, [])

        def give(item, letter):
            if item < 100000:  # a guide page ID in an item field (Demonology's original-item)
                note.append("dropped %d" % item)
                return
            cur = r.get(item)
            if cur is None or ORDER.index(letter) < ORDER.index(cur):
                r[item] = letter

        block = bis_block(m)
        if block is None:
            note.append("no bis_items block")
            rows = table_rows(m[:m.find("Best Gear from Raids")])
        else:
            rows = table_rows(block)
        pieces = set_pieces(spec)
        for label, items in rows:
            for item, orig in items:
                if orig:
                    give(orig, "S")
                    give(item, "A")
                else:
                    give(item, "S")
        for item in catalyze_items(m):
            give(item, "S")
        tiers, labels = trinket_tiers(m)
        note.append("tiers " + "/".join(labels))
        for item, label in tiers.items():
            letter = letter_of(label)
            if letter:
                give(item, letter)
        for item in highlights(m):
            give(item, "A")
        for item in crafted_items(m):
            give(item, "B")
        for p in pieces:
            give(p, "A")
        ranks[spec] = r
    return ranks, notes


def read_bis(path):
    text = open(path, encoding="utf-8").read()
    ranks = {}
    for mm in re.finditer(r"\n    \[(\d+)\] = \{(.*?)\n    \},", text, re.S):
        ranks[int(mm.group(1))] = {int(i): v for i, v in re.findall(r'\[(\d+)\] = "(\w)"', mm.group(2))}
    return ranks


if __name__ == "__main__":
    markups = read_markup()
    ranks, notes = build(markups)
    old = read_bis(os.path.join(ROOT, "Bis.lua"))
    for spec in sorted(ranks):
        new, cur = ranks[spec], old.get(spec, {})
        same = sum(1 for k in new if cur.get(k) == new[k])
        diff = [(k, cur.get(k, "-"), new.get(k, "-")) for k in sorted(set(new) | set(cur)) if cur.get(k) != new.get(k)]
        print("%5d same %3d diff %3d  %s" % (spec, same, len(diff), "; ".join(notes[spec])))
        if "-v" in sys.argv:
            print("      " + " ".join("%d:%s>%s" % x for x in diff))
