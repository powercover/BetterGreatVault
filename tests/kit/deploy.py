"""Copies the addon into the game's AddOns folder as the release zip holds it: the tracked files
(and new ones not ignored) minus dot-files, tests/ and Listing/. Files in the game folder that the
addon no longer has are removed. Prints what changed.

python deploy.py            (BGV_ADDONS overrides the AddOns folder)

A new file or a TOC change needs a game restart; other changes need /reload.
"""
import filecmp
import os
import shutil
import subprocess

REPO = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
DEST = os.path.join(os.environ.get("BGV_ADDONS", r"C:\Program Files (x86)\World of Warcraft\_retail_\Interface\AddOns"),
                    "BetterGreatVault")
SKIP = ("tests/", "Listing/", ".")


def files():
    out = subprocess.run(["git", "ls-files", "--cached", "--others", "--exclude-standard"], cwd=REPO,
                         capture_output=True, text=True, check=True).stdout
    return sorted(p for p in out.splitlines() if p and not p.startswith(SKIP) and "/." not in p)


def main():
    wanted = files()
    copied, removed = [], []
    for path in wanted:
        src, dst = os.path.join(REPO, path), os.path.join(DEST, path)
        if not os.path.exists(src):
            continue
        if not os.path.exists(dst) or not filecmp.cmp(src, dst, shallow=False):
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
            copied.append(path)
    keep = {os.path.normcase(os.path.join(DEST, p)) for p in wanted}
    for folder, _, names in os.walk(DEST):
        for name in names:
            full = os.path.join(folder, name)
            if os.path.normcase(full) not in keep:
                os.remove(full)
                removed.append(os.path.relpath(full, DEST))
    print("copied:", ", ".join(copied) or "nothing")
    print("removed:", ", ".join(removed) or "nothing")
    print(len(wanted), "files in the game folder")


if __name__ == "__main__":
    main()
