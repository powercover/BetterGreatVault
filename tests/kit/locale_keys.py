"""The addon's translation keys (its English text), and a check of every locale file against them.

python locale_keys.py            list the keys
python locale_keys.py --check    check Locales/*.lua: unknown keys, placeholders, color codes, missing
"""
import glob
import os
import re
import sys

ROOT = os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
os.chdir(ROOT)

LUA_STRING = r'"((?:[^"\\]|\\.)*)"'
# Labels kept in tables and translated where they're shown (L[option.label] and the like).
TABLE_LABELS = [
    "All gear", "Head", "Neck", "Shoulder", "Cloak", "Chest", "Wrist", "Hands", "Waist", "Legs", "Feet",
    "Finger", "Trinket", "Weapon",
    "Critical Strike", "Crit", "Haste", "Mastery", "Versatility", "Vers",
    "Raid", "Mythic+", "World", "M+ keystones",
    "Left-click", "Middle-click", "Possible loot from your slots", "Shift + middle-click",
    "Loot database, any class", "Right-click", "Settings", "Drag", "Move this button",
    "Normal", "Heroic", "Mythic Keystone", "Mythic", "Raid Finder",
    "Item", "Tier", "Item Level", "Secondary stats", "Slot",
    "Vault Door", "Classic", "One-Armed Bandit", "Arcane Portal", "Frost Shatter", "Fel Fire", "Old Cartoon",
    # where world loot comes from (WorldLoot.lua), translated as Rewards lists it
    "Delves", "Prey", "World Boss",
]


def unescape(text):
    return text.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")


def code_keys():
    keys = set(TABLE_LABELS)
    for path in glob.glob("*.lua"):
        source = open(path, encoding="utf-8").read()
        for match in re.finditer(r'\bL\[' + LUA_STRING + r'\]', source):
            keys.add(unescape(match.group(1)))
        for match in re.finditer(r'GameText\("\w+", ' + LUA_STRING + r'\)', source):
            keys.add(unescape(match.group(1)))
        # the specialization styles' names (CaseStyles.lua), shown as L[style.name]
        for match in re.finditer(r'\bRegister\("\w+", ' + LUA_STRING, source):
            keys.add(unescape(match.group(1)))
        # the specialization styles' names (CaseStyles.lua), shown as L[style.name]
        for match in re.finditer(r'Register\("\w+", ' + LUA_STRING, source):
            keys.add(unescape(match.group(1)))
    return keys


def placeholders(text):
    return re.findall(r"%[-+ #0]*\d*(?:\.\d+)?[sdifx]|%%", text)


def color_codes(text):
    return (len(re.findall(r"\|c[0-9a-fA-F]{8}", text)), text.count("|r"))


def locale_strings(path):
    source = open(path, encoding="utf-8").read()
    pairs = re.findall(r'\[' + LUA_STRING + r'\]\s*=\s*' + LUA_STRING, source)
    return [(unescape(key), unescape(value)) for key, value in pairs]


def check():
    keys = code_keys()
    problems = 0
    for path in sorted(glob.glob("Locales/*.lua")):
        if path.endswith("Locales.lua"):
            continue
        pairs = locale_strings(path)
        seen = {}
        for key, value in pairs:
            if key in seen:
                print(f"{path}: duplicate key {key!r}")
                problems += 1
            seen[key] = value
            if key not in keys:
                print(f"{path}: unknown key {key!r}")
                problems += 1
                continue
            if placeholders(key) != placeholders(value):
                print(f"{path}: placeholders differ for {key!r}: {placeholders(key)} vs {placeholders(value)}")
                problems += 1
            if color_codes(key) != color_codes(value):
                print(f"{path}: color codes differ for {key!r}")
                problems += 1
            if not value.strip():
                print(f"{path}: empty translation for {key!r}")
                problems += 1
        missing = sorted(keys - set(seen))
        print(f"{os.path.basename(path)}: {len(seen)} translated, {len(missing)} missing")
        for key in missing:
            print(f"    missing: {key!r}")
        problems += len(missing)
    print("locale problems:", problems)
    return problems


if __name__ == "__main__":
    if "--check" in sys.argv:
        sys.exit(1 if check() else 0)
    for key in sorted(code_keys(), key=str.lower):
        print(key)
    print(len(code_keys()), "keys", file=sys.stderr)
