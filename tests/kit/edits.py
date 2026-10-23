"""Exact-match edits on the addon's files, keeping their line endings (most are CRLF).

    from edits import edit, replace_all
    edit(root, "UI.lua", [(old, new), ...])          each `old` must occur exactly once
    replace_all(root, "Case.lua", old, new, count)   every occurrence; asserts the count
"""
import os


def _load(root, path):
    full = os.path.join(root, path)
    raw = open(full, "rb").read().decode("utf-8")
    crlf = "\r\n" in raw
    return full, crlf, raw.replace("\r\n", "\n")


def _save(full, crlf, text):
    if crlf:
        text = text.replace("\n", "\r\n")
    open(full, "wb").write(text.encode("utf-8"))


def edit(root, path, pairs):
    full, crlf, text = _load(root, path)
    for old, new in pairs:
        n = text.count(old)
        assert n == 1, (path, old[:100], n)
        text = text.replace(old, new)
    _save(full, crlf, text)
    print(path, "ok", len(pairs), "edits")


def replace_all(root, path, old, new, count):
    full, crlf, text = _load(root, path)
    n = text.count(old)
    assert n == count, (path, old, n, count)
    _save(full, crlf, text.replace(old, new))
    print(path, "ok", n, "replacements")
