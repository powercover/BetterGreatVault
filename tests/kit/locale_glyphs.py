"""Lists characters in the addon's texts that the game's fonts can't draw.

Fonts come from the game's Slug cache (slug_cmap.py): Friz Quadrata TT (Latin), FrizQuadrataCTT
(Cyrillic), 2002 (Korean), AR ZhongkaiGBK (simplified Chinese), AR Kaiti B5 (traditional Chinese).
"""
import glob
import os
import re
import sys

import slug_cmap

sys.stdout.reconfigure(encoding="utf-8")
ROOT = os.environ.get("BGV_ROOT", os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..")))
FONT_FILES = {"latin": "615960", "cyrillic": "615971", "korean": "615968", "hans": "615974", "hant": "615965"}
fonts = {}
for key, name in FONT_FILES.items():
    fonts[key] = slug_cmap.read(os.path.join(slug_cmap.FONTS, name + ".slug"))[2]

# The fonts a language's text is drawn with (the Latin font covers digits and ASCII everywhere).
LANGUAGE_FONTS = {
    "ruRU": ["cyrillic"], "ukUA": ["cyrillic"], "koKR": ["korean"], "zhCN": ["hans"], "zhTW": ["hant"],
}


def strings(path):
    text = open(path, encoding="utf-8").read()
    return re.findall(r'\] = "((?:[^"\\]|\\.)*)"', text)


def report(label, texts, font_keys):
    problems = {}
    for text in texts:
        for char in set(text):
            if ord(char) < 0x80:
                continue
            in_script = any(ord(char) in fonts[k] for k in font_keys)
            in_latin = ord(char) in fonts["latin"]
            if not in_script:
                problems.setdefault(char, [in_latin, []])[1].append(text)
    if not problems:
        print(f"{label}: every character is in its font")
        return
    for char, (in_latin, examples) in sorted(problems.items()):
        where = "only in the Latin font" if in_latin else "in NO game font"
        print(f"{label}: {char!r} U+{ord(char):04X} {where}, {len(examples)} strings, e.g. {examples[0][:70]!r}")


for path in sorted(glob.glob(os.path.join(ROOT, "Locales", "*.lua"))):
    code = os.path.splitext(os.path.basename(path))[0]
    if code == "Locales":
        continue
    report(code, strings(path), LANGUAGE_FONTS.get(code, ["latin"]))

# The English text: every quoted string in the addon's Lua files.
english = []
for path in glob.glob(os.path.join(ROOT, "*.lua")):
    english += re.findall(r'"((?:[^"\\]|\\.)*)"', open(path, encoding="utf-8").read())
report("English (source)", english, ["latin"])
