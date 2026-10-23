"""Reads the character maps of WoW's cached Slug fonts (_retail_/Fonts/*.slug).

Layout worked out from the files: "guls" magic, then at 0x50 a block of uint32 values whose
offsets are relative to 0x50: chunk count, chunk directory, page table length, page table,
pages, glyph count. The page table holds one uint16 per 256-code-point page (0xFFFF = none);
each page holds 256 uint32 glyph indices (0 = no glyph).
"""
import glob
import os
import struct
import sys

sys.stdout.reconfigure(encoding="utf-8")
FONTS = r"C:\Program Files (x86)\World of Warcraft\_retail_\Fonts"


def read(path):
    data = open(path, "rb").read()
    if data[:4] != b"guls":
        return None
    base = 0x50
    chunks, chunk_dir, table_len, table_off, pages_off, glyphs = struct.unpack_from("<6I", data, base)
    names = []
    for index in range(chunks):
        entry = base + chunk_dir + index * 8
        tag = data[entry:entry + 4][::-1].decode("latin-1")
        (offset,) = struct.unpack_from("<I", data, entry + 4)
        if tag in ("NAME", "SNAM"):
            start = entry + offset
            names.append(data[start:data.index(b"\0", start)].decode("latin-1"))
    table = struct.unpack_from(f"<{table_len}H", data, base + table_off)
    cmap = {}
    for page_number, page in enumerate(table):
        if page == 0xFFFF:
            continue
        entries = struct.unpack_from("<256I", data, base + pages_off + page * 1024)
        for low, glyph in enumerate(entries):
            if glyph != 0:
                cmap[page_number * 256 + low] = glyph
    return " ".join(names), glyphs, cmap


CHECK = {
    "Ukrainian": "ЄІЇҐєіїґ",
    "Russian": "АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя",
    "punctuation": "ʼ’‘«»…—–№·•“”„",
}

if __name__ == "__main__":
    for path in sorted(glob.glob(os.path.join(FONTS, "*.slug"))):
        result = read(path)
        if not result:
            print(os.path.basename(path), "not a slug file")
            continue
        name, glyphs, cmap = result
        print(f"== {os.path.basename(path)}: {name} ({glyphs} glyphs, {len(cmap)} code points)")
        for label, chars in CHECK.items():
            missing = [c for c in chars if ord(c) not in cmap]
            print(f"   {label}: {'all present' if not missing else 'missing ' + ' '.join(f'{c}(U+{ord(c):04X})' for c in missing)}")
